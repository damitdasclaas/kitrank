defmodule KitrankWeb.Reveal.NewLive do
  @moduledoc """
  Einstieg ins Reveal: einem Raum beitreten oder einen aufmachen.

  Der Raumcode ist kurz und zum Vorlesen gedacht. Die Steuerung hängt nicht an
  ihm, sondern an einem eigenen langen Token – sonst könnte jeder, der den Code
  hat, das Reveal weiterschalten.

  Nach dem Anlegen wird deshalb nicht sofort weitergeleitet: erst muss das
  Host-Token im Browser liegen, sonst betritt der Ersteller seinen eigenen Raum
  ohne Steuerung.
  """
  use KitrankWeb, :live_view

  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias Kitrank.Reveal

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()
    competitions = Enum.filter(Kits.list_competitions(), &(&1.id in seasons_competitions(season)))

    {:ok,
     assign(socket,
       page_title: "Reveal",
       max: 8,
       room: nil,
       code_error: nil,
       season: season,
       competitions: competitions,
       # Standard: alles, was es in dieser Saison gibt. Einschraenken kann man
       # danach – aufmachen muss man nichts.
       chosen_leagues: MapSet.new(competitions, & &1.id),
       chosen_types: MapSet.new(available_types(season)),
       types: available_types(season),
       scope_error: nil
     )}
  end

  @impl true
  def handle_event("toggle_league", %{"id" => id}, socket) do
    {:noreply, update(socket, :chosen_leagues, &toggle(&1, String.to_integer(id)))}
  end

  def handle_event("toggle_type", %{"type" => type}, socket) do
    {:noreply, update(socket, :chosen_types, &toggle(&1, type))}
  end

  def handle_event("join", %{"room_code" => code}, socket) do
    case Reveal.fetch_room(code) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/reveal/#{room.room_code}")}

      {:error, :expired} ->
        {:noreply, assign(socket, :code_error, "Dieser Raum ist abgelaufen.")}

      {:error, :not_found} ->
        {:noreply, assign(socket, :code_error, "Diesen Code kennen wir nicht. Vertippt?")}
    end
  end

  @impl true
  def handle_event("create", %{"max_participants" => max}, socket) do
    cond do
      MapSet.size(socket.assigns.chosen_leagues) == 0 ->
        {:noreply, assign(socket, :scope_error, "Wähl mindestens eine Liga.")}

      MapSet.size(socket.assigns.chosen_types) == 0 ->
        {:noreply, assign(socket, :scope_error, "Wähl mindestens einen Trikot-Typ.")}

      true ->
        create_room(socket, max)
    end
  end

  defp create_room(socket, max) do
    attrs = %{
      max_participants: String.to_integer(max),
      season: socket.assigns.season,
      competition_ids: MapSet.to_list(socket.assigns.chosen_leagues),
      kit_types: MapSet.to_list(socket.assigns.chosen_types)
    }

    case Reveal.create_room(attrs) do
      {:ok, room} ->
        {:noreply, assign(socket, room: room, page_title: "Raum #{room.room_code}")}

      {:error, _changeset} ->
        {:noreply, assign(socket, :scope_error, "Der Raum ließ sich nicht anlegen. Nochmal?")}
    end
  end

  defp toggle(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp seasons_competitions(season) do
    season |> Kits.overview() |> Enum.map(fn {competition, _teams} -> competition.id end)
  end

  defp available_types(season) do
    vorhanden = season |> Kits.list_kits() |> MapSet.new(& &1.kit_type)
    Enum.filter(Kit.kit_types(), &MapSet.member?(vorhanden, &1))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl px-4 py-16 sm:px-6">
        <p class="kr-eyebrow">Reveal</p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">Gemeinsam aufdecken</h1>
        <p class="mt-4 text-sm leading-relaxed text-soft">
          Ihr geht eure Ranglisten Platz für Platz durch — vom letzten Rang nach vorn. Bei jedem
          Schritt deckt jede:r das eigene Trikot selbst auf.
        </p>

        <div :if={!@room} class="mt-8 grid gap-4 sm:grid-cols-2">
          <.join_form error={@code_error} />
          <.setup_form
            max={@max}
            season={@season}
            competitions={@competitions}
            chosen_leagues={@chosen_leagues}
            types={@types}
            chosen_types={@chosen_types}
            error={@scope_error}
          />
        </div>

        <.how_it_works :if={!@room} />
        <.room_opened :if={@room} room={@room} />
      </div>
    </Layouts.app>
    """
  end

  attr :error, :string, default: nil

  defp join_form(assigns) do
    ~H"""
    <div class="rounded-xl border border-line bg-panel p-5">
      <h2 class="kr-display text-lg">Raum beitreten</h2>
      <p class="mt-1 text-xs text-soft">Du hast einen Code bekommen?</p>

      <form phx-submit="join" class="mt-4">
        <label for="room_code" class="sr-only">Raumcode</label>
        <input
          id="room_code"
          name="room_code"
          required
          maxlength="8"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          placeholder="ABC23"
          class="kr-display w-full rounded-md border border-line bg-panel px-3 py-3 text-center text-2xl tracking-[0.2em] uppercase placeholder:text-soft/40"
        />
        <p :if={@error} class="mt-2 text-xs text-red-600">{@error}</p>

        <button
          type="submit"
          phx-disable-with="Suche …"
          class="mt-3 w-full rounded-md border border-ink px-4 py-2.5 text-sm font-semibold transition hover:bg-sunk"
        >
          Beitreten
        </button>
      </form>
    </div>
    """
  end

  attr :max, :integer, required: true
  attr :season, :string, required: true
  attr :competitions, :list, required: true
  attr :chosen_leagues, :any, required: true
  attr :types, :list, required: true
  attr :chosen_types, :any, required: true
  attr :error, :string, default: nil

  defp setup_form(assigns) do
    ~H"""
    <form phx-submit="create" class="rounded-xl border border-line bg-panel p-5">
      <h2 class="kr-display text-lg">Raum erstellen</h2>
      <p class="mt-1 text-xs text-soft">Du bekommst einen Code zum Weitergeben.</p>

      <%!-- Der Ausschnitt ist das Wichtigste an dieser Seite: er sorgt dafuer,
            dass "Platz 3" spaeter bei allen dasselbe bedeutet. --%>
      <fieldset class="mt-4">
        <legend class="kr-eyebrow">Worum geht es? · {@season}</legend>

        <div class="mt-2 flex flex-wrap gap-1.5">
          <.chip
            :for={competition <- @competitions}
            event="toggle_league"
            value={competition.id}
            key="id"
            label={competition.name}
            on?={MapSet.member?(@chosen_leagues, competition.id)}
          />
        </div>

        <div class="mt-2 flex flex-wrap gap-1.5">
          <.chip
            :for={type <- @types}
            event="toggle_type"
            value={type}
            key="type"
            label={Kit.label(type)}
            on?={MapSet.member?(@chosen_types, type)}
          />
        </div>

        <p class="mt-2 text-xs text-soft">
          Alle Ranglisten werden auf diesen Ausschnitt gefiltert — dadurch vergleicht ihr
          dieselben Trikots, egal wie lang eure Listen sind.
        </p>
      </fieldset>

      <p :if={@error} class="mt-2 text-xs text-red-600">{@error}</p>

      <label for="max" class="mt-4 block text-xs font-medium">Wie viele macht ihr mit?</label>
      <select
        id="max"
        name="max_participants"
        class="mt-1.5 w-full rounded-md border border-line bg-panel px-3 py-2.5 text-sm"
      >
        <option :for={n <- 2..12} value={n} selected={n == @max}>{n} Personen</option>
      </select>
      <p class="mt-1.5 text-xs text-soft">
        Lässt sich später nicht ändern.
      </p>

      <button
        type="submit"
        phx-disable-with="Raum wird geöffnet …"
        class="mt-3 w-full rounded-md bg-ink px-4 py-2.5 text-sm font-semibold text-chalk transition hover:opacity-90"
      >
        Raum öffnen
      </button>
    </form>
    """
  end

  attr :event, :string, required: true
  attr :value, :any, required: true
  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :on?, :boolean, required: true

  defp chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@key == "id" && @value}
      phx-value-type={@key == "type" && @value}
      aria-pressed={to_string(@on?)}
      class={[
        "rounded-full border px-3 py-1 text-xs transition",
        @on? && "border-transparent bg-ink text-chalk",
        !@on? && "border-line text-soft hover:border-ink hover:text-ink"
      ]}
    >
      {@label}
    </button>
    """
  end

  defp how_it_works(assigns) do
    ~H"""
    <div class="mt-8 rounded-lg border border-line p-5">
      <h2 class="kr-eyebrow">So läuft es ab</h2>
      <ol class="mt-3 space-y-2 text-sm text-soft">
        <li><span class="text-ink">1.</span> Du bekommst einen Raumcode und gibst ihn weiter.</li>
        <li>
          <span class="text-ink">2.</span>
          Alle treten mit dem Teilen-Link ihrer Rangliste bei — nicht mit dem Bearbeiten-Link.
        </li>
        <li>
          <span class="text-ink">3.</span> Du startest, und alle sehen jeden Schritt gleichzeitig.
        </li>
      </ol>
      <p class="mt-3 text-xs text-soft">
        Der Raum läuft nach zwölf Stunden ab. Du kannst die Steuerung im Raum an jemand
        anderen abgeben.
      </p>
    </div>
    """
  end

  attr :room, :map, required: true

  defp room_opened(assigns) do
    ~H"""
    <%!-- Legt das Host-Token ab, bevor irgendwohin navigiert wird. --%>
    <div
      id="remember-host"
      phx-hook="RememberHost"
      data-code={@room.room_code}
      data-host-token={@room.host_token}
      hidden
    >
    </div>

    <div class="kr-rise mt-8 rounded-xl border border-line bg-panel p-6 text-center">
      <p class="kr-eyebrow">Raumcode</p>
      <p class="kr-display mt-2 text-6xl tracking-[0.15em]">{@room.room_code}</p>

      <div class="mt-5 flex flex-wrap items-center justify-center gap-2">
        <button
          type="button"
          id="copy-room-code"
          phx-hook="CopyLink"
          data-copy={@room.room_code}
          class="rounded-md border border-line px-3 py-2 text-xs font-medium transition hover:border-ink"
        >
          <span data-copy-label>Code kopieren</span>
        </button>
        <button
          type="button"
          id="copy-room-link"
          phx-hook="CopyLink"
          data-copy={url(~p"/reveal/#{@room.room_code}")}
          class="rounded-md border border-line px-3 py-2 text-xs font-medium transition hover:border-ink"
        >
          <span data-copy-label>Link kopieren</span>
        </button>
      </div>

      <.link
        navigate={~p"/reveal/#{@room.room_code}"}
        class="mt-6 block w-full rounded-md bg-ink px-4 py-3 text-sm font-semibold text-chalk transition hover:opacity-90"
      >
        Raum betreten
      </.link>

      <p class="mt-4 text-xs text-soft">
        Du steuerst das Reveal. Das merkt sich dein Browser — auf einem anderen Gerät musst du
        die Steuerung im Raum übernehmen lassen.
      </p>
    </div>
    """
  end
end
