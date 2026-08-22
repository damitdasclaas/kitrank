defmodule KitrankWeb.Reveal.NewLive do
  @moduledoc """
  Einen Reveal-Raum aufmachen.

  Der Raumcode ist kurz und zum Vorlesen gedacht. Die Steuerung hängt nicht an
  ihm, sondern an einem eigenen langen Token – sonst könnte jeder, der den Code
  hat, das Reveal weiterschalten.

  Nach dem Anlegen wird deshalb nicht sofort weitergeleitet: erst muss das
  Host-Token im Browser liegen, sonst betritt der Ersteller seinen eigenen Raum
  ohne Steuerung.
  """
  use KitrankWeb, :live_view

  alias Kitrank.Reveal

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Reveal starten", max: 8, room: nil)}
  end

  @impl true
  def handle_event("create", %{"max_participants" => max}, socket) do
    case Reveal.create_room(%{max_participants: String.to_integer(max)}) do
      {:ok, room} ->
        {:noreply, assign(socket, room: room, page_title: "Raum #{room.room_code}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Der Raum ließ sich nicht anlegen. Nochmal?")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl px-4 py-16 sm:px-6">
        <p class="kr-eyebrow">Reveal</p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">Gemeinsam aufdecken</h1>
        <p class="mt-4 text-sm leading-relaxed text-soft">
          Ihr deckt eure Ranglisten Platz für Platz auf — vom letzten Rang nach vorn, und bei
          jedem Schritt zeigen alle gleichzeitig, was bei ihnen dort steht.
        </p>

        <.setup_form :if={!@room} max={@max} />
        <.room_opened :if={@room} room={@room} />
      </div>
    </Layouts.app>
    """
  end

  attr :max, :integer, required: true

  defp setup_form(assigns) do
    ~H"""
    <form phx-submit="create" class="mt-8">
      <label for="max" class="text-sm font-medium">Wie viele macht ihr mit?</label>
      <select
        id="max"
        name="max_participants"
        class="mt-1.5 w-full rounded-md border border-line bg-panel px-3 py-2.5 text-sm"
      >
        <option :for={n <- 2..12} value={n} selected={n == @max}>{n} Personen</option>
      </select>
      <p class="mt-1.5 text-xs text-soft">
        Lässt sich später nicht ändern. Ab etwa acht wird es auf kleinen Bildschirmen eng.
      </p>

      <button
        type="submit"
        phx-disable-with="Raum wird geöffnet …"
        class="mt-6 w-full rounded-md bg-ink px-4 py-3 text-sm font-semibold text-chalk transition hover:opacity-90"
      >
        Raum öffnen
      </button>
    </form>

    <div class="mt-10 rounded-lg border border-line p-5">
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
