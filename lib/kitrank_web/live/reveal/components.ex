defmodule KitrankWeb.Reveal.Components do
  @moduledoc """
  Bausteine des Reveal-Raums.

  Der wichtigste Teil ist `stage/1`: bei jedem Schritt zeigen alle Teilnehmer
  gleichzeitig, was bei ihnen auf diesem Rang steht. Auf kleinen Bildschirmen
  bleiben die Karten deshalb nebeneinander und werden gewischt, statt gestapelt
  zu werden – gestapelt sieht man nie zwei gleichzeitig, und genau darum geht
  es in diesem Moment.
  """
  use KitrankWeb, :html

  import KitrankWeb.KitComponents, only: [kit_figure: 1]

  alias Kitrank.Kits.Kit
  alias KitrankWeb.Color

  attr :room, :map, required: true
  attr :host?, :boolean, required: true
  attr :online, :integer, required: true
  attr :scope, :string, default: nil

  def room_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-line pb-5">
      <div>
        <p class="kr-eyebrow">Raumcode</p>
        <p class="kr-display text-3xl tracking-[0.12em]">{@room.room_code}</p>
      </div>

      <p :if={@scope} class="min-w-0 text-xs text-soft">
        <span class="kr-eyebrow block">Ausschnitt</span>
        {@scope}
      </p>

      <div class="ml-auto flex items-center gap-4">
        <span class="flex items-center gap-1.5 text-xs text-soft">
          <span class="h-2 w-2 rounded-full bg-emerald-500" aria-hidden="true" />
          {@online} online
        </span>
        <span :if={@host?} class="rounded-full border border-ink px-2.5 py-1 font-mono text-[10px]">
          Du steuerst
        </span>
      </div>
    </div>
    """
  end

  attr :error, :string, default: nil
  attr :full?, :boolean, required: true

  @doc "Beitritt über den Teilen-Link der eigenen Rangliste."
  def join_panel(assigns) do
    ~H"""
    <div class="mt-8 rounded-xl border border-line bg-panel p-6">
      <h2 class="kr-display text-xl">Mitmachen</h2>
      <p class="mt-1.5 text-sm text-soft">
        Du brauchst den <span class="text-ink">Teilen-Link</span>
        deiner Rangliste — den mit <code class="font-mono text-xs">/r/</code>, nicht den zum Bearbeiten.
      </p>

      <p :if={@full?} class="mt-4 rounded-md border border-line bg-sunk px-3 py-2 text-sm">
        Der Raum ist voll.
      </p>

      <form :if={!@full?} phx-submit="join" class="mt-5 grid gap-3 sm:grid-cols-[1fr_auto]">
        <div class="grid gap-3 sm:grid-cols-2">
          <div>
            <label for="display_name" class="kr-eyebrow">Dein Name</label>
            <input
              id="display_name"
              name="display_name"
              required
              maxlength="40"
              placeholder="Tom"
              class="mt-1.5 w-full rounded-md border border-line bg-panel px-3 py-2.5 text-sm"
            />
          </div>
          <div>
            <label for="share_slug" class="kr-eyebrow">Teilen-Link</label>
            <input
              id="share_slug"
              name="share_slug"
              required
              placeholder="/r/AbCd1234"
              class="mt-1.5 w-full rounded-md border border-line bg-panel px-3 py-2.5 font-mono text-xs"
            />
          </div>
        </div>

        <button
          type="submit"
          phx-disable-with="Trete bei …"
          class="self-end rounded-md bg-ink px-5 py-2.5 text-sm font-semibold text-chalk transition hover:opacity-90"
        >
          Beitreten
        </button>
      </form>

      <p :if={@error} class="mt-3 text-sm text-red-600">{@error}</p>

      <p class="mt-4 text-xs text-soft">
        Noch keine Rangliste?
        <.link navigate={~p"/rankings/new"} class="text-ink underline underline-offset-4">
          In zwei Minuten gebaut
        </.link>
      </p>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :participants, :list, required: true
  attr :online, :map, required: true
  attr :me, :any, required: true
  attr :host?, :boolean, required: true
  attr :owner?, :boolean, required: true
  attr :fit, :map, default: nil

  @doc "Warteraum: wer ist da, wer steuert."
  def lobby(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="flex items-baseline gap-3">
        <h2 class="kr-display text-xl">Wer ist dabei</h2>
        <span class="font-mono text-xs text-soft">
          {length(@participants)} / {@room.max_participants}
        </span>
      </div>

      <p :if={@participants == []} class="mt-4 text-sm text-soft">
        Noch niemand. Gib den Code <span class="font-mono text-ink">{@room.room_code}</span> weiter.
      </p>

      <ul :if={@participants != []} class="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        <li
          :for={participant <- @participants}
          class="flex items-center gap-3 rounded-lg border border-line bg-panel px-4 py-3"
        >
          <span
            class={[
              "h-2 w-2 shrink-0 rounded-full",
              online?(@online, participant) && "bg-emerald-500",
              !online?(@online, participant) && "bg-line"
            ]}
            title={if online?(@online, participant), do: "online", else: "gerade weg"}
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 truncate text-sm">
            {participant.display_name}
            <span :if={participant.id == @me} class="text-soft">(du)</span>
          </span>
          <span
            :if={@room.host_participant_id == participant.id}
            class="shrink-0 font-mono text-[10px] text-soft"
          >
            steuert
          </span>
          <button
            :if={@host? && @room.host_participant_id != participant.id}
            type="button"
            phx-click="transfer_host"
            phx-value-id={participant.id}
            class="shrink-0 text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
          >
            Steuerung geben
          </button>
        </li>
      </ul>

      <.fit_warning :if={@fit && length(@participants) > 1} fit={@fit} />

      <p :if={@owner? && @room.host_participant_id} class="mt-4 text-xs text-soft">
        Die Steuerung liegt gerade bei jemand anderem.
        <button
          type="button"
          phx-click="reclaim_host"
          class="text-ink underline underline-offset-4"
        >
          Zurückholen
        </button>
      </p>
    </div>
    """
  end

  defp online?(online, participant), do: Map.has_key?(online, to_string(participant.id))

  attr :fit, :map, required: true

  # Der Reveal vergleicht Rang gegen Rang. Passen die Listen nicht zusammen,
  # kann die App das nicht reparieren – aber sie soll es nicht verschweigen,
  # solange sich noch etwas daran aendern laesst.
  defp fit_warning(assigns) do
    ~H"""
    <div class="mt-5 rounded-lg border border-line bg-sunk p-4">
      <p class="kr-eyebrow">Abdeckung des Ausschnitts</p>

      <ul class="mt-2 space-y-1 text-sm">
        <li :for={{name, count} <- @fit.lengths} class="flex items-baseline gap-2">
          <span class="min-w-0 flex-1 truncate text-soft">{name}</span>
          <span class="font-mono tabular-nums">
            {count}<span class="text-soft">/{@fit.scope_size}</span>
          </span>
        </li>
      </ul>

      <p :if={@fit.longest != @fit.shortest} class="mt-2 text-xs leading-relaxed text-soft">
        Das Reveal läuft über {@fit.longest} Plätze. Bei den ersten {@fit.longest - @fit.shortest} zeigen nicht alle etwas — wer will, ergänzt vorher
        noch seine Rangliste.
      </p>
      <p :if={@fit.longest == @fit.shortest and @fit.longest > 0} class="mt-2 text-xs text-soft">
        Alle haben gleich viele Trikots im Ausschnitt. Kann losgehen.
      </p>
      <p :if={@fit.longest == 0} class="mt-2 text-xs text-red-600">
        Niemand hat ein Trikot aus diesem Ausschnitt bewertet — so gibt es nichts aufzudecken.
      </p>
    </div>
    """
  end

  attr :board, :map, required: true
  attr :open?, :boolean, required: true
  attr :me, :any, required: true

  @doc """
  Gesamtübersicht über den bisherigen Verlauf.

  Zeigt nur, was schon offen ist – vergangene Runden vollständig, die laufende
  nur, soweit umgedreht wurde. Bei mehr als zwei Spalten scrollt sie waagerecht,
  die Rang-Spalte bleibt dabei stehen.
  """
  def board(assigns) do
    ~H"""
    <div class="mt-10 border-t border-line pt-6">
      <button
        type="button"
        phx-click="toggle_board"
        aria-expanded={to_string(@open?)}
        class="flex w-full items-center gap-2 text-left"
      >
        <h2 class="kr-display text-lg">Gesamtübersicht</h2>
        <span class="font-mono text-[11px] text-soft">
          {length(@board.rows)} {if length(@board.rows) == 1, do: "Platz", else: "Plätze"} offen
        </span>
        <.icon
          name={if @open?, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
          class="ml-auto size-4 text-soft"
        />
      </button>

      <div :if={@open?} class="mt-4 overflow-x-auto rounded-lg border border-line">
        <table class="w-full min-w-max border-collapse text-sm">
          <thead>
            <tr class="border-b border-line bg-sunk">
              <th class="kr-eyebrow sticky left-0 z-10 bg-sunk px-3 py-2.5 text-left">Platz</th>
              <th
                :for={participant <- @board.participants}
                class="kr-eyebrow min-w-[9rem] px-3 py-2.5 text-left"
              >
                {participant.name}
                <span :if={participant.id == @me} class="normal-case">(du)</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @board.rows} class="border-b border-line last:border-0">
              <td class="kr-display sticky left-0 z-10 bg-panel px-3 py-2 text-right text-base tabular-nums">
                {row.step}
              </td>
              <.board_cell :for={cell <- row.cells} cell={cell} />
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :cell, :map, required: true

  defp board_cell(assigns) do
    assigns =
      assign(assigns, :color, assigns.cell.kit && Color.team_color(assigns.cell.kit.team))

    ~H"""
    <td class="px-3 py-2 align-middle">
      <span :if={!@cell.visible?} class="font-mono text-xs text-soft/60">verdeckt</span>
      <span :if={@cell.visible? && !@cell.kit} class="font-mono text-xs text-soft/60">—</span>

      <span :if={@cell.visible? && @cell.kit} class="flex items-center gap-2">
        <span
          class="flex h-8 w-8 shrink-0 items-center justify-center rounded"
          style={"background-color: color-mix(in oklab, #{@color} 15%, #FFFFFF)"}
        >
          <.kit_figure kit={@cell.kit} team={@cell.kit.team} class="h-6 w-6" size={:thumb} />
        </span>
        <span class="min-w-0">
          <span class="block font-mono text-[11px] font-semibold" style={"color: #{@color}"}>
            {@cell.kit.team.short_code}
          </span>
          <span class="block text-[11px] text-soft">{Kit.display_label(@cell.kit)}</span>
        </span>
      </span>
    </td>
    """
  end

  attr :result, :map, required: true
  attr :room, :map, required: true

  @doc """
  Die Auswertung nach dem Aufdecken.

  Kein Durchschnitt als Hauptdarsteller: der größte Streitfall steht oben, weil
  er die Zeile ist, die man weiterschickt.
  """
  def result_panel(assigns) do
    ~H"""
    <div class="mt-10 border-t border-line pt-8">
      <p class="kr-eyebrow">Auswertung</p>
      <h2 class="kr-display mt-1.5 text-3xl">Wie einig wart ihr?</h2>
      <p class="mt-2 text-sm text-soft">
        Verglichen werden die {@result.shared_count} Trikots, die <span class="text-ink">alle</span>
        bewertet haben.
      </p>

      <div
        :if={@result.shared_count == 0}
        class="mt-6 rounded-lg border border-dashed border-line p-8 text-center text-sm text-soft"
      >
        Ihr hattet kein einziges Trikot gemeinsam in der Liste — da gibt es nichts zu vergleichen.
      </div>

      <div :if={@result.shared_count > 0} class="mt-6 space-y-8">
        <.split_card :if={@result.biggest_split} split={@result.biggest_split} />

        <div class="grid gap-6 sm:grid-cols-2">
          <.consensus_list
            title="Darauf konntet ihr euch einigen"
            kits={@result.consensus_top}
            hint="niedrigster Schnitt"
          />
          <.consensus_list
            title="Das mochte niemand"
            kits={@result.consensus_bottom}
            hint="höchster Schnitt"
          />
        </div>

        <div :if={@result.pairs != []}>
          <h3 class="kr-eyebrow">Wer liegt beieinander</h3>
          <ul class="mt-3 space-y-1.5">
            <li :for={paar <- @result.pairs} class="flex items-baseline gap-3 text-sm">
              <span class="min-w-0 flex-1 truncate">
                {paar.a} <span class="text-soft">und</span> {paar.b}
              </span>
              <span class="shrink-0 font-mono tabular-nums text-soft">
                {:erlang.float_to_binary(paar.distance, decimals: 1)} Plätze auseinander
              </span>
            </li>
          </ul>
          <p class="mt-2 text-xs text-soft">
            Mittlerer Abstand der Platzierungen. 0 heißt: identische Ranglisten.
          </p>
        </div>

        <div :if={@result.notes != []}>
          <h3 class="kr-eyebrow">Was gesagt wurde</h3>
          <ul class="mt-3 space-y-3">
            <li :for={notiz <- @result.notes} class="border-l-2 border-line pl-3">
              <p class="text-sm leading-relaxed">{notiz.note}</p>
              <p class="mt-0.5 text-[11px] text-soft">
                {notiz.participant_name} · Platz {notiz.position} · {notiz.kit.team.short_code} {Kit.display_label(
                  notiz.kit
                )}
              </p>
            </li>
          </ul>
        </div>

        <p class="border-t border-line pt-4 text-xs text-soft">
          Dieser Raum bleibt unter dem Code <span class="font-mono text-ink">{@room.room_code}</span>
          erreichbar, bis er abläuft — der Link zeigt weiterhin diese Auswertung.
        </p>
      </div>
    </div>
    """
  end

  attr :split, :map, required: true

  defp split_card(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.split.kit.team))

    ~H"""
    <div :if={@split.spread > 0} class="rounded-xl border border-line bg-panel p-5">
      <h3 class="kr-eyebrow">Größter Streitfall</h3>

      <div class="mt-3 flex flex-wrap items-center gap-4">
        <span
          class="flex h-20 w-20 shrink-0 items-center justify-center rounded-lg"
          style={"background-color: color-mix(in oklab, #{@color} 14%, #FFFFFF)"}
        >
          <.kit_figure kit={@split.kit} team={@split.kit.team} class="h-16 w-16" size={:thumb} />
        </span>

        <div class="min-w-0">
          <p class="flex flex-wrap items-baseline gap-x-2">
            <span class="font-mono text-xs font-semibold" style={"color: #{@color}"}>
              {@split.kit.team.short_code}
            </span>
            <span class="text-sm font-medium">{@split.kit.team.name}</span>
            <span class="text-xs text-soft">{Kit.display_label(@split.kit)}</span>
          </p>
          <p class="mt-1.5 text-sm">
            <span :for={{eintrag, i} <- Enum.with_index(@split.positions)}>
              <span :if={i > 0} class="text-soft"> · </span>
              {eintrag.participant_name}
              <span class="font-mono tabular-nums text-soft">Platz {eintrag.position}</span>
            </span>
          </p>
          <p class="mt-1 font-mono text-[11px] text-soft">
            {@split.spread} Plätze Unterschied
          </p>
        </div>
      </div>
    </div>

    <div :if={@split.spread == 0} class="rounded-xl border border-line bg-panel p-5">
      <h3 class="kr-eyebrow">Kein Streit</h3>
      <p class="mt-2 text-sm text-soft">
        Ihr habt jedes gemeinsame Trikot auf denselben Platz gesetzt. Das ist entweder
        beeindruckend oder verdächtig.
      </p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :kits, :list, required: true
  attr :hint, :string, required: true

  defp consensus_list(assigns) do
    ~H"""
    <div>
      <h3 class="kr-eyebrow">{@title}</h3>
      <ul class="mt-3 space-y-2">
        <li :for={eintrag <- @kits} class="flex items-center gap-3">
          <span
            class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md"
            style={"background-color: color-mix(in oklab, #{Color.team_color(eintrag.kit.team)} 14%, #FFFFFF)"}
          >
            <.kit_figure
              kit={eintrag.kit}
              team={eintrag.kit.team}
              class="h-8 w-8"
              size={:thumb}
            />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm">{eintrag.kit.team.name}</span>
            <span class="block text-[11px] text-soft">{Kit.display_label(eintrag.kit)}</span>
          </span>
          <span class="shrink-0 font-mono text-xs tabular-nums text-soft">
            {:erlang.float_to_binary(eintrag.average, decimals: 1)}
          </span>
        </li>
      </ul>
      <p class="mt-2 text-[11px] text-soft">{@hint}</p>
    </div>
    """
  end

  @doc "Hinweis für alle, die zuschauen, ohne mitzumachen."
  def spectator_hint(assigns) do
    ~H"""
    <p class="mt-6 rounded-lg border border-dashed border-line px-4 py-3 text-xs text-soft">
      Du schaust nur zu — du bist keiner Rangliste in diesem Raum zugeordnet und hast deshalb
      nichts aufzudecken.
    </p>
    """
  end

  attr :room, :map, required: true
  attr :entries, :list, required: true
  attr :me, :any, required: true
  attr :host?, :boolean, required: true

  @doc """
  Der aufgedeckte Rang: alle Teilnehmer gleichzeitig, nebeneinander.

  Auf schmalen Bildschirmen wird gewischt (Scroll-Snap pro Karte) statt
  gestapelt – siehe Architektur 9.3.
  """
  def stage(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="flex flex-wrap items-baseline gap-3">
        <p class="kr-eyebrow">{if @room.status == "done", do: "Fertig", else: "Aufgedeckt"}</p>
        <h2 class="kr-display text-4xl leading-none">Platz {@room.current_step}</h2>
        <p :if={@room.status == "done"} class="text-sm text-soft">
          Das war's — ihr seid durch.
        </p>
      </div>

      <div
        class={[
          "mt-6 flex snap-x snap-mandatory gap-4 overflow-x-auto pb-4",
          "sm:grid sm:snap-none sm:overflow-visible sm:pb-0",
          grid_class(length(@entries))
        ]}
        role="list"
      >
        <.reveal_card
          :for={entry <- @entries}
          entry={entry}
          mine?={entry.participant_id == @me}
        />
      </div>

      <p class="mt-2 text-xs text-soft sm:hidden">
        Zum nächsten Teilnehmer wischen.
      </p>
    </div>
    """
  end

  # Bis vier Karten passen sie nebeneinander; darueber wird umgebrochen, statt
  # sie immer schmaler zu quetschen.
  defp grid_class(count) when count <= 1, do: "sm:grid-cols-1"
  defp grid_class(2), do: "sm:grid-cols-2"
  defp grid_class(3), do: "sm:grid-cols-2 lg:grid-cols-3"
  defp grid_class(4), do: "sm:grid-cols-2 lg:grid-cols-4"
  defp grid_class(_many), do: "sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"

  attr :entry, :map, required: true
  attr :mine?, :boolean, required: true

  defp reveal_card(assigns) do
    assigns =
      assign(assigns, :color, assigns.entry.kit && Color.team_color(assigns.entry.kit.team))

    ~H"""
    <div
      role="listitem"
      class={[
        "kr-rise flex w-[82vw] shrink-0 snap-center flex-col overflow-hidden rounded-xl border bg-panel",
        "sm:w-auto sm:shrink",
        @mine? && "border-ink",
        !@mine? && "border-line"
      ]}
    >
      <div class="flex items-center gap-2 border-b border-line px-4 py-2.5">
        <span class="min-w-0 flex-1 truncate text-sm font-medium">
          {@entry.participant_name}
        </span>
        <span :if={@mine?} class="shrink-0 font-mono text-[10px] text-soft">du</span>
        <span
          :if={!@entry.revealed? && !@mine?}
          class="shrink-0 font-mono text-[10px] text-soft"
        >
          verdeckt
        </span>
      </div>

      <%!-- Verdeckt: nur die eigene Karte hat einen Knopf. Fremde Karten
            bleiben zu, bis ihr Besitzer sie selbst umdreht. --%>
      <div
        :if={!@entry.revealed?}
        class="flex aspect-square flex-col items-center justify-center gap-4 bg-sunk px-6 text-center"
      >
        <span class="kr-display text-4xl text-soft/40" aria-hidden="true">?</span>
        <button
          :if={@mine?}
          type="button"
          phx-click="reveal_own"
          phx-disable-with="…"
          class="rounded-md bg-ink px-5 py-2.5 text-sm font-semibold text-chalk transition hover:opacity-90"
        >
          Aufdecken
        </button>
        <p :if={!@mine?} class="text-xs text-soft">
          {@entry.participant_name} deckt noch auf
        </p>
      </div>

      <div
        :if={@entry.revealed? && @entry.kit}
        class="flex aspect-square items-center justify-center p-6"
        style={"background-color: color-mix(in oklab, #{@color} 14%, #FFFFFF)"}
      >
        <.kit_figure kit={@entry.kit} team={@entry.kit.team} class="h-full w-full" />
      </div>

      <div
        :if={@entry.revealed? && !@entry.kit}
        class="flex aspect-square items-center justify-center bg-sunk px-6 text-center"
      >
        <p class="text-xs text-soft">Liste reicht nicht so weit</p>
      </div>

      <div :if={@entry.revealed? && @entry.kit} class="px-4 py-3">
        <p class="flex flex-wrap items-baseline gap-x-2">
          <span class="font-mono text-xs font-semibold" style={"color: #{@color}"}>
            {@entry.kit.team.short_code}
          </span>
          <span class="text-sm">{@entry.kit.team.name}</span>
          <span class="text-xs text-soft">{Kit.display_label(@entry.kit)}</span>
        </p>
        <p :if={@entry.note} class="mt-2 text-sm leading-relaxed text-soft">
          {@entry.note}
        </p>
      </div>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :ready?, :boolean, required: true
  attr :revealed, :integer, default: 0
  attr :total, :integer, default: 0
  attr :all_revealed?, :boolean, default: false

  @doc "Die Steuerung – nur für den, der sie gerade hat."
  def host_bar(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-panel/95 backdrop-blur">
      <div class="mx-auto flex max-w-[1500px] items-center gap-3 px-4 py-3 sm:px-6 lg:px-8">
        <p class="min-w-0 text-sm">
          <span :if={@room.status == "waiting"} class="text-soft">
            {if @ready?, do: "Alle da? Dann los.", else: "Warte auf Teilnehmer."}
          </span>
          <span :if={@room.status == "revealing"} class="text-soft">
            <span class="font-mono tabular-nums text-ink">{@revealed}/{@total}</span>
            aufgedeckt · noch
            <span class="font-mono tabular-nums text-ink">{@room.current_step}</span>
            {if @room.current_step == 1, do: "Platz", else: "Plätze"}
          </span>
        </p>

        <button
          type="button"
          phx-click="reveal_next"
          disabled={@room.status == "waiting" && !@ready?}
          phx-disable-with="…"
          class={[
            "ml-auto rounded-md px-5 py-2.5 text-sm font-semibold transition disabled:opacity-40",
            @room.status == "waiting" || (@all_revealed? && "bg-ink text-chalk hover:opacity-90"),
            @room.status != "waiting" && !@all_revealed? &&
              "border border-line text-soft hover:border-ink hover:text-ink"
          ]}
          title={
            if @room.status != "waiting" && !@all_revealed?,
              do: "Es haben noch nicht alle aufgedeckt – du kannst trotzdem weiter."
          }
        >
          {cond do
            @room.status == "waiting" -> "Reveal starten"
            @room.current_step == 1 -> "Abschließen"
            true -> "Nächster Platz"
          end}
        </button>
      </div>
    </div>
    """
  end
end
