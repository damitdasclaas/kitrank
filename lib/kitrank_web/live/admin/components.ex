defmodule KitrankWeb.Admin.Components do
  @moduledoc """
  Gemeinsame Hülle für die Admin-Bereiche.

  Alle fünf Bereiche sind dasselbe Muster – Liste, Formular im Modal, Löschen –
  und teilen sich deshalb Navigation, Tabelle und Formularrahmen. Die Bereiche
  selbst enthalten nur noch, was sie wirklich unterscheidet: ihre Felder.
  """
  use KitrankWeb, :html

  import KitrankWeb.KitComponents, only: [modal: 1]

  @sections [
    {"Sportarten", "/admin/sportarten"},
    {"Ligen", "/admin/ligen"},
    {"Vereine", "/admin/vereine"},
    {"Saison", "/admin/saison"},
    {"Trikots", "/admin/trikots"}
  ]

  def sections, do: @sections

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :current_path, :string, required: true
  attr :new_path, :string, default: nil
  attr :new_label, :string, default: "Neu"
  slot :inner_block, required: true

  @doc "Kopf, Navigation und Rahmen eines Admin-Bereichs."
  def admin_shell(assigns) do
    ~H"""
    <div class="mx-auto max-w-[1200px] px-4 py-10 sm:px-6 lg:px-8">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/admin"} class="kr-eyebrow hover:text-ink">Admin</.link>
        <span class="text-soft">/</span>
        <span class="kr-eyebrow !text-ink">{@title}</span>
        <.link navigate={~p"/"} class="ml-auto text-xs text-soft underline-offset-4 hover:underline">
          Zur Übersicht
        </.link>
      </div>

      <nav class="mt-4 flex flex-wrap gap-1 border-b border-line pb-3">
        <.link
          :for={{label, path} <- sections()}
          navigate={path}
          class={[
            "rounded-md px-3 py-1.5 text-sm transition",
            String.starts_with?(@current_path, path) && "bg-sunk font-medium text-ink",
            !String.starts_with?(@current_path, path) && "text-soft hover:text-ink"
          ]}
        >
          {label}
        </.link>
      </nav>

      <div class="mt-8 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="kr-display text-3xl">{@title}</h1>
          <p :if={@subtitle} class="mt-1.5 max-w-xl text-sm text-soft">{@subtitle}</p>
        </div>
        <.link
          :if={@new_path}
          patch={@new_path}
          class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-chalk transition hover:opacity-90"
        >
          {@new_label}
        </.link>
      </div>

      <div class="mt-6">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :season, :string, required: true
  attr :seasons, :list, required: true
  attr :leagues, :list, default: []

  attr :league_filter, :any,
    required: true,
    doc: "MapSet der gewaehlten Liga-IDs; leer heisst alle"

  attr :search, :string, required: true
  attr :search_placeholder, :string, default: "Suchen …"
  attr :count_label, :string, required: true

  slot :extra, doc: "weitere Filterreihen, direkt unter der Liga-Zeile"

  @doc """
  Saison, Ligenfilter und Suche — die Werkzeugleiste über einer Admin-Liste.

  Erwartet vom Bereich die Ereignisse `select_season`, `toggle_league`,
  `all_leagues`, `search` und `clear_search`. Gemeinsam, weil Vereine und
  Trikots dieselben Fragen an dieselben Daten stellen und es verwirrend wäre,
  wenn die Bedienung sich zwischen den Reitern unterscheidet.
  """
  def admin_toolbar(assigns) do
    ~H"""
    <div class="mb-5 space-y-3">
      <div class="flex flex-wrap items-center gap-2">
        <span class="kr-eyebrow">Saison</span>
        <div class="flex flex-wrap gap-1 rounded-lg border border-line bg-sunk p-1">
          <button
            :for={option <- @seasons}
            type="button"
            phx-click="select_season"
            phx-value-season={option}
            data-role="season"
            class={[
              "rounded-md px-3 py-1.5 font-mono text-xs transition",
              option == @season && "bg-panel text-ink shadow-sm",
              option != @season && "text-soft hover:text-ink"
            ]}
            aria-pressed={to_string(option == @season)}
          >
            {option}
          </button>
        </div>

        <form phx-change="search" id="admin-suche" class="relative ml-auto">
          <label for="q" class="sr-only">Suchen</label>
          <input
            type="search"
            id="q"
            name="q"
            value={@search}
            phx-debounce="250"
            autocomplete="off"
            placeholder={@search_placeholder}
            class="w-56 rounded-md border border-line bg-panel py-1.5 pl-3 pr-8 text-xs focus:border-ink focus:outline-none"
          />
          <button
            :if={@search != ""}
            type="button"
            phx-click="clear_search"
            data-role="clear-search"
            class="absolute right-1.5 top-1/2 flex size-5 -translate-y-1/2 items-center justify-center rounded-full text-soft transition hover:text-ink"
            aria-label="Suche zurücksetzen"
          >
            <.icon name="hero-x-mark-mini" class="size-3.5" />
          </button>
        </form>

        <span class="shrink-0 whitespace-nowrap font-mono text-xs text-soft">{@count_label}</span>
      </div>

      <.filter_row
        :if={@leagues != []}
        label="Liga"
        event="toggle_league"
        all_event="all_leagues"
        selected={@league_filter}
        items={Enum.map(@leagues, &{&1.id, &1.name})}
        role="league"
      />

      {render_slot(@extra)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :all_event, :string, required: true
  attr :selected, :any, required: true, doc: "MapSet; leer heisst alle"
  attr :items, :list, required: true, doc: "Liste von {wert, beschriftung}"
  attr :role, :string, required: true, doc: "data-role der Knoepfe, damit Tests sie treffen"

  @doc """
  Eine Reihe Filter-Chips mit „Alle" davor.

  „Alle" ist der leere Filter und kein eigener Wert: sonst gäbe es zwei
  Zustände, die dasselbe zeigen, und einer davon wäre irgendwann falsch.
  """
  def filter_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <span class="kr-eyebrow">{@label}</span>
      <button
        type="button"
        phx-click={@all_event}
        data-role={"#{@role}-all"}
        aria-pressed={to_string(MapSet.size(@selected) == 0)}
        class={[
          "rounded-full border px-3 py-1 text-xs transition",
          MapSet.size(@selected) == 0 && "border-transparent bg-ink text-chalk",
          MapSet.size(@selected) > 0 && "border-line text-soft hover:border-ink hover:text-ink"
        ]}
      >
        Alle
      </button>
      <button
        :for={{wert, beschriftung} <- @items}
        type="button"
        phx-click={@event}
        phx-value-id={wert}
        data-role={@role}
        aria-pressed={to_string(MapSet.member?(@selected, wert))}
        class={[
          "rounded-full border px-3 py-1 text-xs transition",
          MapSet.member?(@selected, wert) && "border-transparent bg-ink text-chalk",
          !MapSet.member?(@selected, wert) && "border-line text-soft hover:border-ink hover:text-ink"
        ]}
      >
        {beschriftung}
      </button>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :empty_text, :string, default: "Noch nichts angelegt."

  slot :col do
    attr :label, :string, required: true
    attr :class, :string
  end

  slot :actions

  @doc "Tabelle mit einheitlichem Leerzustand."
  def admin_table(assigns) do
    ~H"""
    <div
      :if={@rows == []}
      class="rounded-lg border border-dashed border-line px-6 py-12 text-center text-sm text-soft"
    >
      {@empty_text}
    </div>

    <div :if={@rows != []} class="overflow-x-auto rounded-lg border border-line">
      <table class="w-full min-w-[640px] text-sm">
        <thead>
          <tr class="border-b border-line bg-sunk">
            <th :for={col <- @col} class={["kr-eyebrow px-4 py-2.5 text-left", col[:class]]}>
              {col.label}
            </th>
            <th :if={@actions != []} class="px-4 py-2.5"><span class="sr-only">Aktionen</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="border-b border-line last:border-0 hover:bg-sunk/60">
            <td :for={col <- @col} class={["px-4 py-3 align-middle", col[:class]]}>
              {render_slot(col, row)}
            </td>
            <td :if={@actions != []} class="px-4 py-3 text-right whitespace-nowrap">
              {render_slot(@actions, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :close_path, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  @doc "Formular im Modal – für Anlegen und Bearbeiten derselbe Rahmen."
  def form_modal(assigns) do
    ~H"""
    <.modal id="admin-form" close_path={@close_path} label={@title} size="max-w-xl">
      <div class="border-b border-line px-6 py-5">
        <h2 class="kr-display text-xl">{@title}</h2>
        <p :if={@hint} class="mt-1 text-sm text-soft">{@hint}</p>
      </div>
      <div class="px-6 py-5">{render_slot(@inner_block)}</div>
    </.modal>
    """
  end

  attr :close_path, :string, required: true
  attr :submit_label, :string, default: "Speichern"

  @doc "Abbrechen und Speichern, in jedem Admin-Formular gleich."
  def form_actions(assigns) do
    ~H"""
    <div class="mt-6 flex items-center justify-end gap-3 border-t border-line pt-5">
      <.link patch={@close_path} class="text-sm text-soft hover:text-ink">Abbrechen</.link>
      <button
        type="submit"
        phx-disable-with="Speichert …"
        class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-chalk transition hover:opacity-90"
      >
        {@submit_label}
      </button>
    </div>
    """
  end

  attr :navigate, :string, required: true

  @doc """
  Bearbeiten-Link in der Tabelle.

  `patch`, nicht `navigate`: Liste und Formular sind dieselbe LiveView. Ein
  `navigate` würde sie neu aufbauen und dabei Filter, Suche und gewählte Saison
  verwerfen.
  """
  def edit_link(assigns) do
    ~H"""
    <.link
      patch={@navigate}
      class="text-sm text-soft underline-offset-4 hover:text-ink hover:underline"
    >
      Bearbeiten
    </.link>
    """
  end

  attr :id, :any, required: true
  attr :label, :string, default: "Löschen"
  attr :confirm, :string, required: true

  @doc "Löschen mit Rückfrage – ohne Rückfrage gibt es hier keinen Weg zurück."
  def delete_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="delete"
      phx-value-id={@id}
      data-confirm={@confirm}
      class="ml-4 text-sm text-soft underline-offset-4 hover:text-red-600 hover:underline"
    >
      {@label}
    </button>
    """
  end
end
