defmodule KitrankWeb.Ranking.Components do
  @moduledoc """
  Bausteine der Ranglisten-Oberfläche: Kopf mit Teilen-Link, die beiden
  Schritte und eine Zeile der Sortierliste.
  """
  use KitrankWeb, :html

  import KitrankWeb.KitComponents, only: [kit_figure: 1]

  alias KitrankWeb.Color
  alias KitrankWeb.KitLabel

  attr :ranking, :map, required: true
  attr :name_form, :map, required: true
  attr :share_url, :string, required: true
  attr :season, :string, required: true
  attr :count, :integer, required: true

  attr :derived_from, :any,
    default: nil,
    doc: "die geteilte Liste, von der diese abgeleitet ist — der Weg zurueck"

  attr :compact, :boolean,
    default: false,
    doc: """
    Auf dem Handy nur Saison und Name zeigen. Waehrend des Duells sind Teilen
    und der Hinweis dazu nicht das Thema — und sie kosten den Platz, den die
    beiden Trikots brauchen, um gleichzeitig auf den Bildschirm zu passen. Ab
    `sm` steht wieder alles da.
    """

  @doc "Name der Rangliste (direkt änderbar) und der öffentliche Teilen-Link."
  def ranking_header(assigns) do
    ~H"""
    <div class={["border-b border-line", if(@compact, do: "pb-3 sm:pb-6", else: "pb-6")]}>
      <%!-- Merkt die Rangliste im Browser, damit man beim Wiederkommen nicht
            den Bearbeiten-Link braucht. Der Link bleibt der eigentliche
            Zugriffsweg – etwa beim Geraetewechsel. --%>
      <div
        id="remember-ranking"
        phx-hook="RememberRanking"
        data-token={@ranking.edit_token}
        data-slug={@ranking.share_slug}
        data-name={@ranking.display_name}
        hidden
      >
      </div>

      <p class="kr-eyebrow">
        {gettext("Saison %{saison} · %{anzahl} Trikots", saison: @season, anzahl: @count)}
      </p>

      <%!-- Wer seine eigene Liste fertig hat, soll die fremde wiederfinden,
            ohne die Nachricht zu suchen, in der der Link stand. --%>
      <p :if={@derived_from} class="mt-1 text-xs text-soft">
        {gettext("Gebaut zu")}
        <.link
          navigate={~p"/r/#{@derived_from.share_slug}"}
          data-role="back-to-shared"
          class="text-ink underline underline-offset-4"
        >{@derived_from.display_name || gettext("einer geteilten Liste")}</.link>{gettext(
          " — dorthin zurück, sobald du fertig bist."
        )}
      </p>

      <.form for={@name_form} id="ranking-name" phx-change="save_name" class="mt-2">
        <input
          type="text"
          name="ranking[display_name]"
          value={@ranking.display_name}
          placeholder={gettext("Deine Rangliste")}
          phx-debounce="600"
          aria-label={gettext("Name der Rangliste")}
          class="kr-display w-full border-0 bg-transparent p-0 text-3xl leading-tight outline-none placeholder:text-soft/50 focus:ring-0 sm:text-4xl"
        />
      </.form>

      <div class={[
        if(@compact, do: "hidden sm:flex", else: "flex"),
        "mt-5 flex-wrap items-center gap-2"
      ]}>
        <span class="kr-eyebrow">{gettext("Teilen")}</span>
        <code class="min-w-0 flex-1 truncate rounded-md bg-sunk px-3 py-2 font-mono text-xs text-soft">
          {@share_url}
        </code>
        <button
          type="button"
          id="copy-share-link"
          phx-hook="CopyLink"
          data-copy={@share_url}
          class="shrink-0 rounded-md border border-line px-3 py-2 text-xs font-medium transition hover:border-ink"
        >
          <span data-copy-label>{gettext("Link kopieren")}</span>
        </button>
        <.link
          navigate={~p"/r/#{@ranking.share_slug}"}
          class="shrink-0 text-xs text-soft underline-offset-4 hover:text-ink hover:underline"
        >{gettext("Ansehen")}</.link>
      </div>
      <p class={["mt-2 text-xs text-soft", @compact && "hidden sm:block"]}>
        {gettext(
          "Der Teilen-Link zeigt immer den aktuellen Stand — du musst nichts erneut verschicken. Die Adresse in deiner Adresszeile ist dagegen geheim: wer sie hat, kann mitändern."
        )}
      </p>

      <%!-- Wie geteilt wird. Steht direkt beim Link, weil es die Frage ist,
            die man sich beim Verschicken stellt. --%>
      <div class={["mt-4 flex flex-wrap items-center gap-2", @compact && "hidden sm:flex"]}>
        <span class="kr-eyebrow">{gettext("Wer den Link öffnet")}</span>
        <div class="flex gap-1 rounded-lg border border-line bg-sunk p-1">
          <button
            :for={
              {modus, label} <- [
                {"open", gettext("sieht sie")},
                {"gated", gettext("rankt erst selbst")}
              ]
            }
            type="button"
            phx-click="set_share_mode"
            phx-value-mode={modus}
            data-role="share-mode"
            aria-pressed={to_string(@ranking.share_mode == modus)}
            class={[
              "rounded-md px-3 py-1.5 text-xs transition",
              @ranking.share_mode == modus && "bg-panel text-ink shadow-sm",
              @ranking.share_mode != modus && "text-soft hover:text-ink"
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <p
        :if={@ranking.share_mode == "gated"}
        class={["mt-2 text-xs text-soft", @compact && "hidden sm:block"]}
      >
        {gettext(
          "Wer den Link öffnet, bekommt deinen Ausschnitt und muss erst selbst sortieren. Danach seht ihr beide Listen nebeneinander. Gemerkt wird das im Browser des Gegenübers — ein privates Fenster hebt es auf."
        )}
      </p>
    </div>
    """
  end

  attr :live_action, :atom, required: true
  attr :edit_token, :string, required: true
  attr :count, :integer, required: true

  @doc "Umschalter zwischen Auswählen und Sortieren."
  def step_nav(assigns) do
    ~H"""
    <nav
      class="mt-6 flex gap-1 rounded-lg border border-line bg-sunk p-1"
      aria-label={gettext("Schritte")}
    >
      <.link
        patch={~p"/rankings/#{@edit_token}/auswahl"}
        class={step_class(@live_action == :select)}
        aria-current={@live_action == :select && "step"}
      >
        <span class="font-mono text-[11px] opacity-60">1</span> {gettext("Auswählen")}
      </.link>
      <.link
        patch={~p"/rankings/#{@edit_token}/duell"}
        class={step_class(@live_action == :duel)}
        aria-current={@live_action == :duel && "step"}
      >
        <span class="font-mono text-[11px] opacity-60">2</span> {gettext("Vergleichen")}
      </.link>
      <.link
        patch={~p"/rankings/#{@edit_token}/edit"}
        class={step_class(@live_action == :sort)}
        aria-current={@live_action == :sort && "step"}
      >
        <span class="font-mono text-[11px] opacity-60">3</span> {gettext("Sortieren")}
        <span :if={@count > 0} class="font-mono text-[11px] opacity-60">({@count})</span>
      </.link>
    </nav>
    """
  end

  defp step_class(active?) do
    [
      "flex flex-1 items-center justify-center gap-2 rounded-md px-4 py-2 text-sm transition",
      active? && "bg-panel font-medium text-ink shadow-sm",
      !active? && "text-soft hover:text-ink"
    ]
  end

  attr :live_action, :atom, required: true
  attr :edit_token, :string, required: true
  attr :count, :integer, required: true

  @doc "Fortschritt und der Weg zum jeweils anderen Schritt, immer sichtbar."
  def step_bar(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-panel/95 backdrop-blur">
      <div class="mx-auto flex max-w-[1200px] items-center gap-3 px-4 py-3 sm:px-6 lg:px-8">
        <p class="text-sm">
          <span class="font-mono tabular-nums">{@count}</span>
          <span class="text-soft">{ngettext(
            "%{count} Trikot in der Liste",
            "%{count} Trikots in der Liste",
            @count
          )}</span>
        </p>

        <%!-- Zwei Wege nach der Auswahl: die Vergleiche liefern einen Entwurf,
              von Hand geht es auch direkt. --%>
        <div :if={@live_action == :select && @count > 0} class="ml-auto flex items-center gap-2">
          <.link
            patch={~p"/rankings/#{@edit_token}/edit"}
            class="rounded-md border border-line px-4 py-2 text-sm transition hover:border-ink"
          >{gettext("Selbst sortieren")}</.link>
          <.link
            :if={@count > 1}
            patch={~p"/rankings/#{@edit_token}/duell"}
            class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-chalk transition hover:opacity-90"
          >{gettext("Vergleichen lassen")}</.link>
        </div>

        <.link
          :if={@live_action == :sort}
          patch={~p"/rankings/#{@edit_token}/auswahl"}
          class="ml-auto rounded-md border border-line px-4 py-2 text-sm transition hover:border-ink"
        >{gettext("Trikots hinzufügen")}</.link>

        <span :if={@live_action == :select && @count == 0} class="ml-auto text-xs text-soft">{gettext(
          "Tipp auf ein Trikot, um es aufzunehmen"
        )}</span>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :index, :integer, required: true
  attr :last?, :boolean, required: true
  attr :total, :integer, required: true, doc: "Laenge der Liste – die Obergrenze des Platzfeldes"

  attr :note_epoch, :integer,
    default: 0,
    doc: "erzwingt einen Neuaufbau des ignorierten Notizfeldes"

  @doc "Eine Zeile der Sortierliste: Platz, Trikot, Notiz, Griff."
  def entry_row(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.entry.kit.team))

    ~H"""
    <li
      data-kit-id={@entry.kit_id}
      class="flex items-start gap-3 rounded-lg border border-line bg-panel p-3"
    >
      <button
        type="button"
        data-drag-handle
        class="mt-1 hidden cursor-grab touch-none text-soft transition hover:text-ink active:cursor-grabbing sm:block"
        aria-label={gettext("Zum Umsortieren ziehen")}
        tabindex="-1"
      >
        <.icon name="hero-bars-3" class="size-4" />
      </button>

      <%!-- Die Ziffer ist das Feld. Bei zwanzig Trikots ist „auf Platz 3"
            ein Tastendruck, waehrend Pfeile siebzehn Klicks brauchen und
            Ziehen ueber den halben Bildschirm geht.

            phx-blur speichert genauso wie Enter: wer tippt und danach
            woanders hinfasst, hat den Platz gemeint, nicht verworfen. Die
            ID im Namen des Formulars haengt am Trikot und wechselt beim
            Umsortieren nicht mit der Position. --%>
      <form id={"platz-form-#{@entry.kit_id}"} phx-submit="move_to" class="mt-0.5 shrink-0">
        <input type="hidden" name="kit_id" value={@entry.kit_id} />
        <input
          type="number"
          name="position"
          value={@index + 1}
          min="1"
          max={@total}
          inputmode="numeric"
          phx-blur="move_to"
          phx-value-kit-id={@entry.kit_id}
          aria-label={
            gettext("Platz von %{verein} %{trikot}",
              verein: @entry.kit.team.name,
              trikot: KitLabel.display(@entry.kit)
            )
          }
          class="kr-display w-10 rounded-md border border-transparent bg-transparent px-1 py-0.5 text-right text-lg tabular-nums leading-none transition hover:border-line focus:border-ink focus:outline-none"
        />
      </form>

      <button
        type="button"
        phx-click="open_detail"
        phx-value-id={@entry.kit_id}
        data-role="detail-figure"
        class="group relative flex h-20 w-20 shrink-0 items-center justify-center rounded-md transition sm:h-24 sm:w-24"
        style={"background-color: color-mix(in oklab, #{@color} 14%, #FFFFFF)"}
        aria-label={
          gettext("%{verein} %{trikot} im Detail",
            verein: @entry.kit.team.name,
            trikot: KitLabel.display(@entry.kit)
          )
        }
      >
        <.kit_figure
          kit={@entry.kit}
          team={@entry.kit.team}
          class="h-16 w-16 transition-transform duration-300 group-hover:scale-105 sm:h-20 sm:w-20"
          size={:thumb}
        />
        <span
          class="pointer-events-none absolute bottom-1 right-1 flex h-5 w-5 items-center justify-center rounded-full bg-white/85 text-black/60 opacity-0 backdrop-blur transition group-hover:opacity-100 group-focus-within:opacity-100"
          aria-hidden="true"
        >
          <.icon name="hero-arrows-pointing-out-mini" class="size-3" />
        </span>
      </button>

      <div class="min-w-0 flex-1">
        <p class="flex flex-wrap items-baseline gap-x-2">
          <span class="font-mono text-xs font-semibold" style={"color: #{@color}"}>
            {@entry.kit.team.short_code}
          </span>
          <span class="text-sm">{@entry.kit.team.name}</span>
          <span class="text-xs text-soft">{KitLabel.display(@entry.kit)}</span>
          <button
            type="button"
            phx-click="open_detail"
            phx-value-id={@entry.kit_id}
            data-role="detail-link"
            class="text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
          >{gettext("Detail")}</button>
        </p>

        <%!-- Der Server schickt die Notiz nur beim ersten Rendern; sonst wuerde
              ein Speichern waehrend des Tippens den Cursor verlieren. --%>
        <div id={"note-#{@entry.id}-#{@note_epoch}"} phx-update="ignore" class="mt-1.5">
          <form id={"note-form-#{@entry.id}"} phx-change="save_note">
            <input type="hidden" name="entry_id" value={@entry.id} />
            <textarea
              name="note"
              rows="3"
              phx-debounce="600"
              maxlength="500"
              placeholder={gettext("Notiz — warum steht es hier?")}
              aria-label={"Notiz zu #{@entry.kit.team.name} #{KitLabel.display(@entry.kit)}"}
              class="w-full resize-y rounded-md border border-line bg-panel px-2.5 py-1.5 text-xs leading-relaxed placeholder:text-soft/70"
            >{@entry.note}</textarea>
          </form>
        </div>
      </div>

      <div class="flex shrink-0 flex-col gap-1">
        <button
          type="button"
          phx-click="move"
          phx-value-id={@entry.kit_id}
          phx-value-delta="-1"
          disabled={@index == 0}
          class="flex h-6 w-6 items-center justify-center rounded border border-line text-soft transition enabled:hover:border-ink enabled:hover:text-ink disabled:opacity-30"
          aria-label={gettext("Einen Platz nach oben")}
        >
          <.icon name="hero-chevron-up-mini" class="size-3.5" />
        </button>
        <button
          type="button"
          phx-click="move"
          phx-value-id={@entry.kit_id}
          phx-value-delta="1"
          disabled={@last?}
          class="flex h-6 w-6 items-center justify-center rounded border border-line text-soft transition enabled:hover:border-ink enabled:hover:text-ink disabled:opacity-30"
          aria-label={gettext("Einen Platz nach unten")}
        >
          <.icon name="hero-chevron-down-mini" class="size-3.5" />
        </button>
        <button
          type="button"
          phx-click="remove"
          phx-value-id={@entry.kit_id}
          class="flex h-6 w-6 items-center justify-center rounded border border-line text-soft transition hover:border-red-500 hover:text-red-600"
          aria-label={
            gettext("%{verein} %{trikot} aus der Liste nehmen",
              verein: @entry.kit.team.name,
              trikot: KitLabel.display(@entry.kit)
            )
          }
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>
    </li>
    """
  end
end
