defmodule KitrankWeb.Reveal.RoomLive do
  @moduledoc """
  Der Reveal-Raum: beitreten, warten, gemeinsam aufdecken.

  Der Zustand liegt in Postgres, nicht im Prozess. Jeder Schritt des Hosts wird
  geschrieben und dann als fertig geladener Schritt an alle gesendet – kein
  Client lädt nach, kein Polling. Ein Reconnect ist dadurch unspektakulär: beim
  Neuaufbau steht der aktuelle Stand einfach in der Datenbank.

  Presence sagt zusätzlich, wer gerade wirklich verbunden ist. Das ergänzt die
  Teilnehmerliste, ersetzt sie aber nicht – wer kurz das Handy sperrt, fliegt
  nicht aus dem Reveal.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Reveal.Components

  alias Kitrank.Reveal
  alias KitrankWeb.Presence

  @impl true
  def mount(%{"room_code" => code}, _session, socket) do
    case Reveal.fetch_room(code) do
      {:error, :not_found} ->
        raise KitrankWeb.NotFoundError, "Diesen Raum gibt es nicht."

      {:error, :expired} ->
        raise KitrankWeb.NotFoundError, "Dieser Raum ist abgelaufen."

      {:ok, room} ->
        if connected?(socket) do
          Reveal.subscribe(room)
          Phoenix.PubSub.subscribe(Kitrank.PubSub, Presence.topic(room.room_code))
        end

        {:ok,
         socket
         |> assign(
           page_title: "Reveal #{room.room_code}",
           room: room,
           # Wird gleich vom ClaimHost-Hook aus dem Browser nachgereicht.
           host_token: nil,
           # Wer man selbst ist – erst nach dem Beitritt bekannt.
           me: nil,
           join_error: nil,
           online: %{},
           board_open?: true,
           scope_label: scope_label(room)
         )
         |> load_room()}
    end
  end

  # Kurzform des Ausschnitts fuer den Kopf: "Bundesliga · Heim, Auswaerts".
  defp scope_label(room) do
    ligen =
      Kitrank.Kits.list_competitions()
      |> Enum.filter(&(&1.id in room.competition_ids))
      |> Enum.map_join(", ", & &1.name)

    typen = Enum.map_join(room.kit_types, ", ", &Kitrank.Kits.Kit.label/1)

    [ligen, typen] |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")
  end

  ## Host-Erkennung

  @impl true
  def handle_event("claim_host", %{"token" => token}, socket) do
    if Reveal.owner?(socket.assigns.room, token) do
      {:noreply, socket |> assign(:host_token, token) |> assign_host()}
    else
      # Altes Token zu einem neu vergebenen Code – aufräumen statt mitschleppen.
      {:noreply, push_event(socket, "forget_host", %{code: socket.assigns.room.room_code})}
    end
  end

  ## Beitreten

  def handle_event("join", %{"share_slug" => slug, "display_name" => name}, socket) do
    case Reveal.join(socket.assigns.room, extract_slug(slug), name) do
      {:ok, participant} ->
        track(socket, participant)

        {:noreply,
         socket
         |> assign(me: participant.id, join_error: nil)
         |> load_room()}

      {:error, reason} ->
        {:noreply, assign(socket, :join_error, join_message(reason))}
    end
  end

  ## Aufdecken – das eigene Trikot darf jede:r selbst

  def handle_event("reveal_own", _params, socket) do
    case socket.assigns.me do
      nil ->
        {:noreply, socket}

      participant_id ->
        Reveal.reveal_own(socket.assigns.room, participant_id)
        {:noreply, socket}
    end
  end

  def handle_event("toggle_board", _params, socket) do
    {:noreply, update(socket, :board_open?, &(!&1))}
  end

  ## Ablauf – nur der Host

  def handle_event("reveal_next", _params, socket) do
    if host?(socket) do
      {:ok, _room} = Reveal.reveal_next(socket.assigns.room)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("transfer_host", %{"id" => id}, socket) do
    if host?(socket) do
      case Reveal.transfer_host(socket.assigns.room, String.to_integer(id)) do
        {:ok, _room} -> {:noreply, socket}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Übergabe hat nicht geklappt.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reclaim_host", _params, socket) do
    if Reveal.owner?(socket.assigns.room, socket.assigns.host_token) do
      {:ok, _room} = Reveal.reclaim_host(socket.assigns.room)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  ## Broadcasts

  @impl true
  def handle_info({:participants_changed, _participants}, socket) do
    {:noreply, load_room(socket)}
  end

  def handle_info({:step_revealed, _step, _entries}, socket) do
    {:noreply, load_room(socket)}
  end

  def handle_info({:host_changed, _participant_id}, socket) do
    {:noreply, load_room(socket)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_online(socket)}
  end

  ## Laden

  defp load_room(socket) do
    case Reveal.fetch_room(socket.assigns.room.room_code) do
      {:ok, room} ->
        socket
        |> then(fn socket ->
          entries = Reveal.step_entries(room)

          assign(socket,
            room: room,
            participants: room.participants,
            step_entries: entries,
            revealed_count: Enum.count(entries, & &1.revealed?),
            all_revealed?: entries != [] and Enum.all?(entries, & &1.revealed?),
            fit: room.status == "waiting" && Reveal.ranking_fit(room),
            board: room.status != "waiting" && Reveal.revealed_board(room)
          )
        end)
        |> assign_host()
        |> assign_online()

      # Der Raum ist waehrend der Sitzung abgelaufen oder verschwunden.
      {:error, _reason} ->
        socket
        |> put_flash(:error, "Dieser Raum ist abgelaufen.")
        |> push_navigate(to: ~p"/")
    end
  end

  defp assign_host(socket) do
    room = socket.assigns.room

    assign(socket,
      host?: Reveal.host?(room, socket.assigns.host_token, socket.assigns.me),
      owner?: Reveal.owner?(room, socket.assigns.host_token)
    )
  end

  defp assign_online(socket) do
    assign(socket, :online, Presence.list_room(socket.assigns.room.room_code))
  end

  defp host?(socket), do: socket.assigns[:host?] == true

  defp track(socket, participant) do
    if connected?(socket) do
      Presence.track_participant(socket.assigns.room.room_code, to_string(participant.id), %{
        name: participant.display_name
      })
    end
  end

  # Leute fuegen erfahrungsgemaess den ganzen Link ein, nicht den Slug.
  defp extract_slug(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
  end

  defp join_message(:unknown_share_slug),
    do: "Diesen Teilen-Link kennen wir nicht. Er sieht so aus: /r/AbCd1234"

  defp join_message(:room_full), do: "Der Raum ist voll."
  defp join_message(:already_started), do: "Das Reveal läuft schon — zu spät für einen Beitritt."
  defp join_message(:expired), do: "Dieser Raum ist abgelaufen."

  defp join_message(%Ecto.Changeset{} = changeset) do
    if changeset.errors[:room_id],
      do: "Diese Rangliste ist schon dabei.",
      else: "Bitte einen Namen angeben."
  end

  defp join_message(_other), do: "Das hat nicht geklappt."

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="claim-host" phx-hook="ClaimHost" data-code={@room.room_code} hidden></div>

      <div class="mx-auto max-w-[1500px] px-4 py-8 sm:px-6 lg:px-8">
        <.room_header
          room={@room}
          host?={@host?}
          online={map_size(@online)}
          scope={@scope_label}
        />

        <.join_panel
          :if={!@me && @room.status == "waiting"}
          error={@join_error}
          full?={length(@participants) >= @room.max_participants}
        />

        <.lobby
          :if={@room.status == "waiting"}
          room={@room}
          participants={@participants}
          online={@online}
          me={@me}
          host?={@host?}
          owner?={@owner?}
          fit={@fit}
        />

        <.stage
          :if={@room.status != "waiting"}
          room={@room}
          entries={@step_entries}
          me={@me}
          host?={@host?}
        />

        <.spectator_hint :if={!@me && @room.status != "waiting"} />

        <.board :if={@board && @board.rows != []} board={@board} open?={@board_open?} me={@me} />
      </div>

      <.host_bar
        :if={@host? && @room.status != "done"}
        room={@room}
        ready?={@participants != []}
        revealed={@revealed_count}
        total={length(@step_entries)}
        all_revealed?={@all_revealed?}
      />
    </Layouts.app>
    """
  end
end
