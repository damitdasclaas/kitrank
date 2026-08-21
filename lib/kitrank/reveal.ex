defmodule Kitrank.Reveal do
  @moduledoc """
  Live-Räume, in denen mehrere Ranglisten gemeinsam aufgedeckt werden.

  Ablauf: Der Host schaltet weiter, der Server schreibt den neuen `current_step`
  nach Postgres und broadcastet den fertig geladenen Schritt an alle Clients.
  Kein Client lädt selbst nach, kein Polling.

  Der State liegt bewusst in der Datenbank statt in einem GenServer pro Raum –
  für Freundesgruppen reicht "Write + Broadcast" locker, und Reconnects brauchen
  dadurch keine Sonderbehandlung.
  """

  import Ecto.Query, warn: false

  alias Kitrank.Repo
  alias Kitrank.Rankings
  alias Kitrank.Rankings.Ranking
  alias Kitrank.Reveal.{Participant, Room}

  @pubsub Kitrank.PubSub
  @max_code_attempts 5

  ## Räume

  @doc """
  Legt einen Raum an und weist Raumcode, Host-Token und Ablaufzeit zu.

  Der Raumcode ist kurz und wird zufällig gezogen – bei einer Kollision wird neu
  gezogen statt einen Fehler durchzureichen.
  """
  def create_room(attrs \\ %{}, attempts \\ @max_code_attempts) do
    case %Room{} |> Room.create_changeset(attrs) |> Repo.insert() do
      {:ok, room} ->
        {:ok, room}

      {:error, changeset} ->
        if attempts > 1 and Keyword.has_key?(changeset.errors, :room_code) do
          create_room(attrs, attempts - 1)
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Raum per Code, inklusive Teilnehmer.

  Abgelaufene Räume liefern `{:error, :expired}` statt eines halb funktionierenden
  Raums, unbekannte Codes `{:error, :not_found}`.
  """
  def fetch_room(room_code) when is_binary(room_code) do
    room_code = String.upcase(String.trim(room_code))

    case Repo.get_by(Room, room_code: room_code) do
      nil ->
        {:error, :not_found}

      room ->
        room = Repo.preload(room, participants: participants_query())
        if Room.expired?(room), do: {:error, :expired}, else: {:ok, room}
    end
  end

  def fetch_room(_), do: {:error, :not_found}

  @doc "Darf dieses Token den Raum steuern?"
  def host?(%Room{host_token: host_token}, token) when is_binary(token) do
    Plug.Crypto.secure_compare(host_token, token)
  end

  def host?(_room, _token), do: false

  def list_participants(%Room{id: room_id}), do: list_participants(room_id)

  def list_participants(room_id) do
    room_id |> participants_query() |> Repo.all()
  end

  defp participants_query(room_id) do
    from p in participants_query(), where: p.room_id == ^room_id
  end

  defp participants_query do
    from p in Participant, order_by: [asc: p.inserted_at], preload: [:ranking]
  end

  ## Beitritt

  @doc """
  Nimmt eine Rangliste in den Raum auf – identifiziert über ihren öffentlichen
  `share_slug`, das `edit_token` bleibt dabei privat.

  Broadcastet `{:participants_changed, participants}`, damit die Warte-Lobby bei
  allen sofort aktualisiert.
  """
  def join(%Room{} = room, share_slug, display_name) do
    with {:ok, room} <- ensure_joinable(room),
         %Ranking{} = ranking <- Rankings.get_ranking_by_share_slug(share_slug) do
      %Participant{}
      |> Participant.changeset(%{
        room_id: room.id,
        ranking_id: ranking.id,
        display_name: display_name
      })
      |> Repo.insert()
      |> case do
        {:ok, participant} ->
          broadcast(room, {:participants_changed, list_participants(room)})
          {:ok, Repo.preload(participant, :ranking)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :unknown_share_slug}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_joinable(%Room{} = room) do
    cond do
      Room.expired?(room) -> {:error, :expired}
      room.status != "waiting" -> {:error, :already_started}
      count_participants(room.id) >= room.max_participants -> {:error, :room_full}
      true -> {:ok, room}
    end
  end

  defp count_participants(room_id) do
    Repo.one(from p in Participant, where: p.room_id == ^room_id, select: count(p.id))
  end

  ## Ablauf

  @doc """
  Startet das Reveal beim schlechtesten Rang.

  Startrang ist die Länge der längsten beteiligten Rangliste – so fällt niemandes
  Trikot hinten runter, nur weil eine andere Liste kürzer ist.
  """
  def start(%Room{} = room) do
    case starting_step(room) do
      0 -> {:error, :no_entries}
      step -> update_step(room, %{status: "revealing", current_step: step})
    end
  end

  @doc """
  Deckt den nächsten (besseren) Rang auf. Nach Rang 1 wechselt der Raum auf
  "done" und bleibt dort stehen.
  """
  def reveal_next(%Room{status: "waiting"} = room), do: start(room)

  def reveal_next(%Room{current_step: step} = room) when is_integer(step) and step > 1 do
    update_step(room, %{current_step: step - 1})
  end

  def reveal_next(%Room{} = room), do: update_step(room, %{status: "done"})

  defp update_step(%Room{} = room, attrs) do
    room
    |> Room.step_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, room} ->
        broadcast(room, {:step_revealed, room.current_step, step_entries(room)})
        {:ok, room}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp starting_step(%Room{} = room) do
    room
    |> list_participants()
    |> Enum.map(&Rankings.count_entries(&1.ranking_id))
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Was auf dem aktuellen Rang bei allen Teilnehmern steht – eine Liste
  `%{participant_id, participant_name, kit, note}`.

  Wird einmal geladen und mitgebroadcastet, damit kein Client selbst nachlädt.
  `kit` ist `nil`, wenn eine Rangliste so weit nicht reicht; die UI zeigt dort
  eine leere Karte statt den Teilnehmer verschwinden zu lassen.
  """
  def step_entries(%Room{current_step: nil}), do: []

  def step_entries(%Room{current_step: step} = room) do
    room
    |> list_participants()
    |> Enum.map(fn participant ->
      entry = Rankings.get_entry_at(participant.ranking_id, step)

      %{
        participant_id: participant.id,
        participant_name: participant.display_name,
        kit: entry && entry.kit,
        note: entry && entry.note
      }
    end)
  end

  ## PubSub

  @doc "Auf die Events eines Raums hören – im `mount/3` hinter `connected?/1`."
  def subscribe(%Room{room_code: code}), do: subscribe(code)

  def subscribe(room_code) when is_binary(room_code) do
    Phoenix.PubSub.subscribe(@pubsub, Room.topic(room_code))
  end

  defp broadcast(%Room{room_code: code}, message) do
    Phoenix.PubSub.broadcast(@pubsub, Room.topic(code), message)
  end

  ## Aufräumen

  @doc """
  Löscht abgelaufene Räume samt Teilnehmern. Gedacht für einen periodischen Job –
  die Ranglisten selbst bleiben davon unberührt.
  """
  def delete_expired_rooms(now \\ DateTime.utc_now()) do
    {count, _} = Repo.delete_all(from r in Room, where: r.expires_at < ^now)
    count
  end
end
