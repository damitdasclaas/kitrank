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

  alias Kitrank.Kits
  alias Kitrank.Kits.Scope
  alias Kitrank.Repo
  alias Kitrank.Rankings
  alias Kitrank.Rankings.Ranking
  alias Kitrank.Reveal.{Participant, Result, Room}

  @pubsub Kitrank.PubSub
  @max_code_attempts 5

  ## Ausschnitt des Raums

  @doc """
  Der Ausschnitt des Raums als `Kitrank.Kits.Scope`.

  Der Raum führt ihn als drei Spalten – `season` (Einzahl), `competition_ids`,
  `kit_types` –, weil es diese Spalten gab, bevor es den gemeinsamen Begriff
  gab. Hier wird daraus einer.
  """
  def scope(%Room{} = room) do
    %Scope{
      seasons: [room.season],
      competition_ids: room.competition_ids,
      kit_types: room.kit_types
    }
  end

  @doc """
  Die Trikots, um die es in diesem Raum geht – Saison, Ligen und Kit-Typen wie
  beim Anlegen festgelegt.
  """
  def scope_kit_ids(%Room{} = room) do
    room
    |> scope()
    |> Kits.list_kits_for_scope()
    |> MapSet.new(& &1.kit.id)
  end

  @doc "Wie viele Trikots der Ausschnitt umfasst."
  def scope_size(%Room{} = room), do: room |> scope_kit_ids() |> MapSet.size()

  @doc """
  Die Einträge einer Rangliste, auf den Ausschnitt gefiltert und neu
  durchnummeriert.

  Das Umnummerieren ist der Kern: wer im Ausschnitt nur jedes zweite Trikot
  bewertet hat, soll trotzdem einen lückenlosen Platz 1, 2, 3 haben – sonst
  entstünden Runden, in denen niemand etwas zeigt.
  """
  def scoped_entries(%Room{} = room, ranking_id) do
    entries_in_scope(scope_kit_ids(room), ranking_id)
  end

  defp entries_in_scope(scope, ranking_id) do
    ranking_id
    |> Rankings.list_entries()
    |> Enum.filter(&MapSet.member?(scope, &1.kit_id))
  end

  @doc """
  Wie weit eine Rangliste den Ausschnitt abdeckt: `{abgedeckt, gesamt}`.

  Wird beim Beitritt und in der Lobby gezeigt – wer nur drei von vierzig
  Trikots bewertet hat, soll das sehen, bevor es losgeht.
  """
  def coverage(%Room{} = room, ranking_id) do
    scope = scope_kit_ids(room)
    {length(entries_in_scope(scope, ranking_id)), MapSet.size(scope)}
  end

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

  @doc """
  Darf gesteuert werden – entweder mit dem Ersteller-Token oder als der
  Teilnehmer, an den die Steuerung uebergeben wurde.

  Das Ersteller-Token bleibt auch nach einer Uebergabe gueltig. Sonst waere ein
  Raum unsteuerbar, sobald der neue Host das Handy weglegt, und niemand koennte
  ihn retten. Der Ersteller ist der Eigentuemer des Raums – wie beim
  `edit_token` einer Rangliste haengt das Recht am Link.
  """
  def host?(room, token \\ nil, participant_id \\ nil) do
    owner?(room, token) or designated_host?(room, participant_id)
  end

  @doc "Haelt jemand das Ersteller-Token?"
  def owner?(%Room{host_token: host_token}, token) when is_binary(token) do
    Plug.Crypto.secure_compare(host_token, token)
  end

  def owner?(_room, _token), do: false

  @doc "Ist dieser Teilnehmer der Host, an den uebergeben wurde?"
  def designated_host?(%Room{host_participant_id: nil}, _participant_id), do: false
  def designated_host?(_room, nil), do: false

  def designated_host?(%Room{host_participant_id: host_id}, participant_id),
    do: host_id == participant_id

  @doc """
  Gibt die Steuerung an einen Teilnehmer des Raums ab.

  Broadcastet `{:host_changed, participant_id}`, damit die Steuerelemente bei
  allen sofort dort auftauchen, wo sie hingehoeren.
  """
  def transfer_host(%Room{} = room, participant_id) do
    if participant_in_room?(room, participant_id) do
      room
      |> Room.host_changeset(participant_id)
      |> Repo.update()
      |> case do
        {:ok, room} ->
          broadcast(room, {:host_changed, room.host_participant_id})
          {:ok, room}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_a_participant}
    end
  end

  @doc "Der Ersteller holt sich die Steuerung zurueck."
  def reclaim_host(%Room{} = room) do
    room
    |> Room.host_changeset(nil)
    |> Repo.update()
    |> case do
      {:ok, room} ->
        broadcast(room, {:host_changed, nil})
        {:ok, room}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp participant_in_room?(%Room{id: room_id}, participant_id) do
    Repo.exists?(from p in Participant, where: p.id == ^participant_id and p.room_id == ^room_id)
  end

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

  @doc """
  Beitreten, ohne vorher eine Rangliste gebaut zu haben.

  Legt eine Rangliste an, die alle Trikots des Raum-Ausschnitts enthält, und
  tritt damit bei. Sortiert wird danach — im Raum, per Duell.

  Ohne das muss jede:r **vorher** eine Rangliste bauen und den Teilen-Link
  parat haben. Für eine spontane Runde ist das zu viel; damit ist der Beitritt
  ein Name und ein Klick.
  """
  def join_new(%Room{} = room, display_name) do
    with {:ok, room} <- ensure_joinable(room),
         kit_ids = room |> scope_kit_ids() |> MapSet.to_list(),
         false <- kit_ids == [],
         {:ok, ranking} <- Rankings.create_ranking(%{display_name: display_name}) do
      Rankings.add_kits(ranking, sortiert_nach_uebersicht(room, kit_ids))

      # Qualifiziert, weil `import Ecto.Query` ein eigenes join/3 mitbringt.
      case __MODULE__.join(room, ranking.share_slug, display_name) do
        {:ok, participant} -> {:ok, participant, ranking}
        {:error, reason} -> {:error, reason}
      end
    else
      true -> {:error, :empty_scope}
      {:error, reason} -> {:error, reason}
    end
  end

  # In der Reihenfolge der Uebersicht statt zufaellig – so beginnt das Duell
  # mit einer nachvollziehbaren Ausgangslage.
  defp sortiert_nach_uebersicht(%Room{} = room, kit_ids) do
    erlaubt = MapSet.new(kit_ids)

    room
    |> scope()
    |> Kits.list_kits_for_scope()
    |> Enum.map(& &1.kit.id)
    |> Enum.filter(&MapSet.member?(erlaubt, &1))
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
    scope = scope_kit_ids(room)

    room
    |> list_participants()
    |> Enum.map(&length(entries_in_scope(scope, &1.ranking_id)))
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Was auf dem aktuellen Rang bei allen Teilnehmern steht – eine Liste
  `%{participant_id, participant_name, kit, note, revealed?}`.

  Wird einmal geladen und mitgebroadcastet, damit kein Client selbst nachlädt.
  `kit` ist `nil`, wenn eine Rangliste so weit nicht reicht; die UI zeigt dort
  eine leere Karte statt den Teilnehmer verschwinden zu lassen.

  Solche leeren Karten gelten als aufgedeckt – es gibt nichts umzudrehen, und
  sonst würde die Runde auf jemanden warten, der gar nichts zeigen kann.
  """
  def step_entries(%Room{current_step: nil}), do: []

  def step_entries(%Room{current_step: step} = room) do
    scope = scope_kit_ids(room)

    room
    |> list_participants()
    |> Enum.map(fn participant ->
      entry = entries_in_scope(scope, participant.ranking_id) |> Enum.at(step - 1)

      %{
        participant_id: participant.id,
        participant_name: participant.display_name,
        kit: entry && entry.kit,
        note: entry && entry.note,
        revealed?: is_nil(entry) or participant.revealed_step == step
      }
    end)
  end

  @doc """
  Ein Teilnehmer deckt sein eigenes Trikot auf.

  Broadcastet den neuen Stand des Schritts, damit die Karte bei allen
  gleichzeitig umschlägt.
  """
  def reveal_own(%Room{current_step: nil}, _participant_id), do: {:error, :not_started}

  def reveal_own(%Room{current_step: step} = room, participant_id) do
    case Repo.get_by(Participant, id: participant_id, room_id: room.id) do
      nil ->
        {:error, :not_a_participant}

      participant ->
        participant
        |> Participant.reveal_changeset(step)
        |> Repo.update()
        |> case do
          {:ok, participant} ->
            broadcast(room, {:step_revealed, step, step_entries(room)})
            {:ok, participant}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Der bisherige Verlauf als Tabelle: eine Zeile je Rang, eine Spalte je
  Teilnehmer.

  Sichtbar ist nur, was schon aufgedeckt wurde. Die Regel dafür ist bewusst
  einfach: **vergangene Runden sind offen, die laufende zeigt nur, was
  umgedreht wurde.** Sobald der Host weiterschaltet, ist die Runde vorbei –
  eine Karte dann noch dauerhaft zu verstecken, nur weil jemand nicht geklickt
  hat, würde die Tabelle für alle anderen kaputtmachen.

  Gibt `%{participants: [...], rows: [%{step:, cells: [...]}]}` zurück, Zeilen
  vom schlechtesten bereits gezeigten Rang bis zum aktuellen.
  """
  def revealed_board(%Room{current_step: nil}), do: %{participants: [], rows: []}

  def revealed_board(%Room{current_step: current} = room) do
    participants = list_participants(room)
    scope = scope_kit_ids(room)

    # Einmal alle Einträge laden statt pro Zelle zu fragen. Die Position ist
    # die im Ausschnitt, nicht die in der ganzen Rangliste.
    by_participant =
      Map.new(participants, fn participant ->
        entries =
          scope
          |> entries_in_scope(participant.ranking_id)
          |> Enum.with_index(1)
          |> Map.new(fn {entry, position} -> {position, entry} end)

        {participant.id, entries}
      end)

    start = Enum.max([map_size_max(by_participant), current], fn -> current end)

    rows =
      for step <- start..current//-1 do
        cells =
          Enum.map(participants, fn participant ->
            entry = by_participant |> Map.fetch!(participant.id) |> Map.get(step)

            %{
              participant_id: participant.id,
              kit: entry && entry.kit,
              note: entry && entry.note,
              visible?: step > current or is_nil(entry) or participant.revealed_step == current
            }
          end)

        %{step: step, cells: cells}
      end

    %{
      participants: Enum.map(participants, &%{id: &1.id, name: &1.display_name}),
      rows: rows
    }
  end

  defp map_size_max(by_participant) do
    by_participant
    |> Map.values()
    |> Enum.map(&map_size/1)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Die Auswertung nach dem Aufdecken – siehe `Kitrank.Reveal.Result`.

  Verglichen werden nur Trikots aus dem Ausschnitt des Raums, in der Position,
  die sie dort haben.
  """
  def result(%Room{} = room) do
    participants = list_participants(room)
    scope = scope_kit_ids(room)

    entries =
      Map.new(participants, fn p -> {p.id, entries_in_scope(scope, p.ranking_id)} end)

    Result.build(participants, entries)
  end

  @doc """
  Wie gut passen die Ranglisten im Raum zusammen?

  Gibt `%{lengths: [{name, anzahl}], shortest:, longest:, shared:}` zurück –
  `shared` ist die Zahl der Trikots, die wirklich in *allen* Listen vorkommen.

  Der Reveal vergleicht Rang gegen Rang. Wenn eine Liste neun Einträge hat und
  eine andere zwei, laufen sieben Runden als Soloauftritt, und "Platz 2" heißt
  bei beiden etwas völlig Verschiedenes. Das kann die App nicht reparieren –
  aber sie kann es vor dem Start sichtbar machen.
  """
  def ranking_fit(%Room{} = room) do
    participants = list_participants(room)
    scope = scope_kit_ids(room)
    scope_size = MapSet.size(scope)

    lengths =
      Enum.map(participants, fn participant ->
        {participant.display_name, length(entries_in_scope(scope, participant.ranking_id))}
      end)

    counts = Enum.map(lengths, &elem(&1, 1))

    %{
      lengths: lengths,
      shortest: Enum.min(counts, fn -> 0 end),
      longest: Enum.max(counts, fn -> 0 end),
      scope_size: scope_size
    }
  end

  @doc "Haben auf dem aktuellen Rang schon alle aufgedeckt?"
  def all_revealed?(%Room{} = room) do
    room |> step_entries() |> Enum.all?(& &1.revealed?)
  end

  @doc "Wie viele von wie vielen haben aufgedeckt – für die Anzeige beim Host."
  def reveal_progress(%Room{} = room) do
    entries = step_entries(room)
    {Enum.count(entries, & &1.revealed?), length(entries)}
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
