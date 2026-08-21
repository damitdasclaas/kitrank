defmodule KitrankWeb.OverviewLive do
  @moduledoc """
  Die Übersicht: alle Teams einer Saison mit ihren Trikots, nach Liga gruppiert.

  Drei Ansichten teilen sich diesen LiveView, unterschieden über `live_action`:

    * `:index`    – das Raster
    * `:team`     – Team-Detail als Modal über dem Raster
    * `:compare`  – Direktvergleich von zwei oder drei Trikots

  Die Vergleichsauswahl steht im Query-Parameter `trikots` statt im Socket-State.
  Das kostet nichts und macht einen Vergleich teilbar – dieselbe Logik wie bei
  den Ranglisten: Wer den Link hat, sieht dasselbe.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.KitComponents

  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias KitrankWeb.Color

  @max_compare 3

  @impl true
  def mount(_params, _session, socket) do
    seasons = Kits.list_seasons()
    season = List.first(seasons) || Kits.current_season()

    {:ok, socket |> assign(seasons: seasons) |> load_season(season)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign_compare(params)
      |> assign_open_team(params)
      |> assign_page_title()

    {:noreply, socket}
  end

  ## Events

  @impl true
  def handle_event("select_season", %{"season" => season}, socket) do
    # Beim Saisonwechsel fällt die Auswahl weg – sie zeigt auf Trikots, die es
    # in der neuen Saison so nicht gibt.
    {:noreply, socket |> load_season(season) |> push_patch(to: ~p"/")}
  end

  def handle_event("toggle_compare", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.compare_ids

    cond do
      id in selected ->
        {:noreply, patch_compare(socket, List.delete(selected, id))}

      length(selected) >= @max_compare ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Im Vergleich haben drei Trikots Platz. Nimm erst eins heraus."
         )}

      true ->
        {:noreply, patch_compare(socket, selected ++ [id])}
    end
  end

  def handle_event("select_image", %{"kit-id" => kit_id, "index" => index}, socket) do
    choices = Map.put(socket.assigns.image_choice, kit_id, String.to_integer(index))
    {:noreply, assign(socket, :image_choice, choices)}
  end

  ## Assigns

  defp load_season(socket, season) do
    overview = Kits.overview(season)

    kits_by_id =
      for {competition, teams} <- overview,
          {team, kits} <- teams,
          kit <- kits,
          into: %{},
          do: {kit.id, %{kit: kit, team: team, competition: competition}}

    teams_by_id =
      for {competition, teams} <- overview,
          {team, kits} <- teams,
          into: %{},
          do: {team.id, %{team: team, kits: kits, competition: competition}}

    socket
    |> assign(
      season: season,
      overview: overview,
      kits_by_id: kits_by_id,
      teams_by_id: teams_by_id,
      kit_count: map_size(kits_by_id)
    )
    |> assign_new(:image_choice, fn -> %{} end)
    |> assign_new(:compare_ids, fn -> [] end)
    |> assign_new(:open_team, fn -> nil end)
  end

  # Nimmt nur IDs an, die es in dieser Saison wirklich gibt – ein geteilter Link
  # aus der Vorsaison soll nicht mit leeren Karten enden, sondern mit weniger.
  defp assign_compare(socket, params) do
    ids =
      params
      |> Map.get("trikots", "")
      |> String.split(",", trim: true)
      |> Enum.flat_map(fn part ->
        case Integer.parse(part) do
          {id, ""} -> [id]
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(socket.assigns.kits_by_id, &1))
      |> Enum.take(@max_compare)

    assign(socket, :compare_ids, ids)
  end

  defp assign_open_team(%{assigns: %{live_action: :team}} = socket, %{"id" => id}) do
    case Integer.parse(id) do
      {team_id, ""} -> assign(socket, :open_team, Map.get(socket.assigns.teams_by_id, team_id))
      _ -> assign(socket, :open_team, nil)
    end
  end

  defp assign_open_team(socket, _params), do: assign(socket, :open_team, nil)

  defp assign_page_title(socket) do
    title =
      case {socket.assigns.live_action, socket.assigns.open_team} do
        {:team, %{team: team}} -> team.name
        {:compare, _} -> "Direktvergleich"
        _ -> "Übersicht"
      end

    assign(socket, :page_title, title)
  end

  defp patch_compare(socket, ids) do
    push_patch(socket, to: path_for(socket.assigns.live_action, socket.assigns.open_team, ids))
  end

  ## Pfade – die Auswahl reist über alle Ansichten mit

  defp path_for(action, open_team, ids) do
    query = if ids == [], do: %{}, else: %{"trikots" => Enum.join(ids, ",")}

    case {action, open_team} do
      {:team, %{team: team}} -> ~p"/teams/#{team.id}?#{query}"
      {:compare, _} -> ~p"/vergleich?#{query}"
      _ -> ~p"/?#{query}"
    end
  end

  defp index_path(ids), do: path_for(:index, nil, ids)
  defp compare_path(ids), do: path_for(:compare, nil, ids)
  defp team_path(team, ids), do: path_for(:team, %{team: team}, ids)

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-[1500px] px-4 pb-32 pt-10 sm:px-6 lg:px-8">
        <.page_intro
          season={@season}
          seasons={@seasons}
          kit_count={@kit_count}
          team_count={map_size(@teams_by_id)}
        />

        <div
          :if={@overview == []}
          class="mt-16 rounded-lg border border-dashed border-line p-12 text-center"
        >
          <p class="kr-display text-xl">Noch keine Trikots für {@season}</p>
          <p class="mx-auto mt-2 max-w-md text-sm text-soft">
            Trag Ligen, Teams und Trikots im Admin ein — dann füllt sich diese Seite.
          </p>
        </div>

        <section :for={{competition, teams} <- @overview} class="mt-14 first:mt-10">
          <.league_header competition={competition} team_count={length(teams)} />

          <div class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            <.team_tile
              :for={{team, kits} <- teams}
              team={team}
              kits={kits}
              compare_ids={@compare_ids}
              href={team_path(team, @compare_ids)}
            />
          </div>
        </section>
      </div>

      <.compare_tray
        :if={@compare_ids != []}
        compare_ids={@compare_ids}
        kits_by_id={@kits_by_id}
        compare_path={compare_path(@compare_ids)}
        clear_path={index_path([])}
      />

      <.team_modal
        :if={@live_action == :team && @open_team}
        entry={@open_team}
        season={@season}
        compare_ids={@compare_ids}
        image_choice={@image_choice}
        close_path={index_path(@compare_ids)}
      />

      <.compare_modal
        :if={@live_action == :compare}
        compare_ids={@compare_ids}
        kits_by_id={@kits_by_id}
        season={@season}
        close_path={index_path(@compare_ids)}
      />
    </Layouts.app>
    """
  end

  ## Seitenkopf

  attr :season, :string, required: true
  attr :seasons, :list, required: true
  attr :kit_count, :integer, required: true
  attr :team_count, :integer, required: true

  defp page_intro(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 border-b border-line pb-8 md:flex-row md:items-end md:justify-between">
      <div>
        <p class="kr-eyebrow">Saison {@season}</p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95] sm:text-5xl">
          Jedes Trikot<br />der beiden Ligen
        </h1>
        <p class="mt-4 max-w-md text-sm leading-relaxed text-soft">
          {@kit_count} Trikots von {@team_count} Vereinen. Team antippen für alle Varianten,
          oder zwei bis drei Trikots nebeneinanderlegen.
        </p>
      </div>

      <div :if={length(@seasons) > 1} class="flex items-center gap-2">
        <span class="kr-eyebrow">Saison</span>
        <div class="flex gap-1 rounded-lg border border-line bg-sunk p-1">
          <button
            :for={option <- @seasons}
            phx-click="select_season"
            phx-value-season={option}
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
      </div>
    </div>
    """
  end

  attr :competition, :map, required: true
  attr :team_count, :integer, required: true

  defp league_header(assigns) do
    ~H"""
    <div class="flex items-baseline gap-4 border-b border-line pb-2">
      <h2 class="kr-display text-xl">{@competition.name}</h2>
      <span class="kr-eyebrow">
        {@competition.country} · Liga {@competition.tier}
      </span>
      <span class="ml-auto font-mono text-xs text-soft">{@team_count} Vereine</span>
    </div>
    """
  end

  ## Team-Kachel

  attr :team, :map, required: true
  attr :kits, :list, required: true
  attr :compare_ids, :list, required: true
  attr :href, :string, required: true

  defp team_tile(assigns) do
    assigns =
      assigns
      |> assign(:color, Color.team_color(assigns.team))
      |> assign(:lead_kit, lead_kit(assigns.kits))

    ~H"""
    <div class="group relative overflow-hidden rounded-lg border border-line bg-panel transition hover:border-ink/25 hover:shadow-[0_8px_28px_-16px_rgb(0_0_0/0.45)]">
      <%!-- Die Bühne bleibt in beiden Themes hell: Trikots sind Produktfotos,
            und die liegen auf Weiß. --%>
      <div
        class="relative flex aspect-[4/3] items-center justify-center px-6 py-4"
        style={"background-color: color-mix(in oklab, #{@color} 15%, #FFFFFF)"}
      >
        <.kit_figure
          :if={@lead_kit}
          kit={@lead_kit}
          team={@team}
          class="h-full w-full transition-transform duration-300 group-hover:-translate-y-1"
        />
        <span :if={!@lead_kit} class="font-mono text-[11px] text-black/40">kein Trikot</span>

        <button
          :if={@lead_kit}
          type="button"
          phx-click="toggle_compare"
          phx-value-id={@lead_kit.id}
          data-role="tile-compare"
          class={[
            "absolute right-2 top-2 z-20 flex h-7 items-center gap-1 rounded-full border px-2",
            "font-mono text-[10px] font-medium transition",
            @lead_kit.id in @compare_ids && "border-transparent text-white",
            @lead_kit.id not in @compare_ids &&
              "border-black/10 bg-white/85 text-black/60 opacity-0 backdrop-blur focus-visible:opacity-100 group-hover:opacity-100"
          ]}
          style={
            @lead_kit.id in @compare_ids &&
              "background-color: #{@color}; color: #{Color.readable_on(@color)}"
          }
          aria-pressed={to_string(@lead_kit.id in @compare_ids)}
          aria-label={
            if @lead_kit.id in @compare_ids,
              do: "#{@team.name} #{Kit.label(@lead_kit.kit_type)} aus dem Vergleich nehmen",
              else: "#{@team.name} #{Kit.label(@lead_kit.kit_type)} vergleichen"
          }
        >
          <.icon
            name={if @lead_kit.id in @compare_ids, do: "hero-check-mini", else: "hero-plus-mini"}
            class="size-3"
          />
          {if @lead_kit.id in @compare_ids, do: "Drin", else: "Vergleich"}
        </button>
      </div>

      <div class="flex items-center gap-2 border-t border-line px-3 py-2.5">
        <span
          class="font-mono text-xs font-semibold tabular-nums"
          style={"color: #{@color}"}
        >
          {@team.short_code}
        </span>
        <span class="truncate text-[13px] leading-tight">{@team.name}</span>
        <span class="ml-auto flex shrink-0 gap-1">
          <.kit_badge
            :for={kit <- @kits}
            kit_type={kit.kit_type}
            class="bg-sunk text-soft"
          />
        </span>
      </div>

      <%!-- Liegt unter den echten Buttons, deckt aber die ganze Kachel ab. --%>
      <.link patch={@href} class="absolute inset-0 z-10" aria-label={"#{@team.name} — alle Trikots"}>
        <span class="sr-only">{@team.name}</span>
      </.link>
    </div>
    """
  end

  defp lead_kit(kits) do
    Enum.find(kits, &(&1.kit_type == "home")) || List.first(kits)
  end

  ## Vergleichsleiste

  attr :compare_ids, :list, required: true
  attr :kits_by_id, :map, required: true
  attr :compare_path, :string, required: true
  attr :clear_path, :string, required: true

  defp compare_tray(assigns) do
    ~H"""
    <div class="kr-tray fixed inset-x-0 bottom-0 z-40 border-t border-line bg-panel/95 backdrop-blur">
      <div class="mx-auto flex max-w-[1500px] items-center gap-3 px-4 py-3 sm:px-6 lg:px-8">
        <span class="kr-eyebrow hidden shrink-0 sm:block">Vergleich</span>

        <ul class="flex flex-1 items-center gap-2 overflow-x-auto">
          <li :for={id <- @compare_ids} class="shrink-0">
            <.tray_chip entry={@kits_by_id[id]} />
          </li>
          <li :if={length(@compare_ids) < 3} class="shrink-0 font-mono text-[11px] text-soft">
            noch {3 - length(@compare_ids)} möglich
          </li>
        </ul>

        <.link
          patch={@clear_path}
          class="shrink-0 font-mono text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
        >
          Leeren
        </.link>

        <.link
          :if={length(@compare_ids) >= 2}
          patch={@compare_path}
          class="shrink-0 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-chalk transition hover:opacity-90"
        >
          Vergleichen ({length(@compare_ids)})
        </.link>

        <span
          :if={length(@compare_ids) < 2}
          class="shrink-0 font-mono text-[11px] text-soft"
        >
          noch eins dazu
        </span>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp tray_chip(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.entry.team))

    ~H"""
    <div class="flex items-center gap-2 rounded-full border border-line py-1 pl-1 pr-2">
      <span
        class="flex h-6 w-6 items-center justify-center rounded-full"
        style={"background-color: color-mix(in oklab, #{@color} 18%, #FFFFFF)"}
      >
        <.kit_figure kit={@entry.kit} team={@entry.team} class="h-4 w-4" />
      </span>
      <span class="font-mono text-[11px] font-semibold" style={"color: #{@color}"}>
        {@entry.team.short_code}
      </span>
      <span class="text-[11px] text-soft">{Kit.label(@entry.kit.kit_type)}</span>
      <button
        type="button"
        phx-click="toggle_compare"
        phx-value-id={@entry.kit.id}
        data-role="tray-remove"
        class="text-soft transition hover:text-ink"
        aria-label={"#{@entry.team.name} #{Kit.label(@entry.kit.kit_type)} aus dem Vergleich nehmen"}
      >
        <.icon name="hero-x-mark-mini" class="size-3.5" />
      </button>
    </div>
    """
  end

  ## Team-Modal

  attr :entry, :map, required: true
  attr :season, :string, required: true
  attr :compare_ids, :list, required: true
  attr :image_choice, :map, required: true
  attr :close_path, :string, required: true

  defp team_modal(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.entry.team))

    ~H"""
    <.modal
      id="team-modal"
      close_path={@close_path}
      label={"Trikots von #{@entry.team.name}"}
      size="max-w-5xl"
    >
      <div
        class="border-b border-line px-6 py-5"
        style={"background-color: color-mix(in oklab, #{@color} 8%, transparent)"}
      >
        <p class="kr-eyebrow">{@entry.competition.name} · Saison {@season}</p>
        <div class="mt-1.5 flex flex-wrap items-baseline gap-3">
          <h2 class="kr-display text-2xl">{@entry.team.name}</h2>
          <span class="font-mono text-sm font-semibold" style={"color: #{@color}"}>
            {@entry.team.short_code}
          </span>
        </div>
        <a
          :if={@entry.team.shop_url}
          href={@entry.team.shop_url}
          target="_blank"
          rel="noopener noreferrer"
          class="mt-2 inline-flex items-center gap-1 text-xs text-soft underline underline-offset-4 hover:text-ink"
        >
          Vereinsshop <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
        </a>
      </div>

      <div :if={@entry.kits == []} class="px-6 py-12 text-center">
        <p class="text-sm text-soft">
          Für {@entry.team.name} sind in {@season} noch keine Trikots hinterlegt.
        </p>
      </div>

      <div class="grid gap-px bg-line sm:grid-cols-2 lg:grid-cols-3">
        <.kit_panel
          :for={kit <- @entry.kits}
          kit={kit}
          team={@entry.team}
          color={@color}
          selected={kit.id in @compare_ids}
          active_index={Map.get(@image_choice, to_string(kit.id), 0)}
        />
      </div>
    </.modal>
    """
  end

  attr :kit, :map, required: true
  attr :team, :map, required: true
  attr :color, :string, required: true
  attr :selected, :boolean, required: true
  attr :active_index, :integer, required: true

  defp kit_panel(assigns) do
    images = kit_images(assigns.kit)

    assigns =
      assigns
      |> assign(:images, images)
      |> assign(:active_image, Enum.at(images, assigns.active_index))

    ~H"""
    <div class="flex flex-col bg-panel">
      <div
        class="relative flex aspect-square items-center justify-center p-8"
        style={"background-color: color-mix(in oklab, #{@color} 13%, #FFFFFF)"}
      >
        <.kit_figure kit={@kit} team={@team} image_url={@active_image} class="h-full w-full" />
      </div>

      <div :if={length(@images) > 1} class="flex gap-1.5 border-t border-line px-3 py-2">
        <button
          :for={{_url, index} <- Enum.with_index(@images)}
          type="button"
          phx-click="select_image"
          phx-value-kit-id={@kit.id}
          phx-value-index={index}
          class={[
            "h-1.5 flex-1 rounded-full transition",
            index == @active_index && "bg-ink",
            index != @active_index && "bg-line hover:bg-soft"
          ]}
          aria-label={"Bild #{index + 1} von #{length(@images)} zeigen"}
          aria-current={to_string(index == @active_index)}
        />
      </div>

      <div class="flex items-center gap-2 border-t border-line px-4 py-3">
        <div class="min-w-0">
          <p class="text-sm font-medium">{Kit.label(@kit.kit_type)}</p>
          <a
            :if={@kit.source_shop_url}
            href={@kit.source_shop_url}
            target="_blank"
            rel="noopener noreferrer"
            class="mt-0.5 inline-flex items-center gap-1 text-[11px] text-soft underline underline-offset-4 hover:text-ink"
          >
            Im Shop ansehen <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
          </a>
          <p :if={!@kit.source_shop_url} class="mt-0.5 text-[11px] text-soft">
            Kein Shop-Link hinterlegt
          </p>
        </div>

        <button
          type="button"
          phx-click="toggle_compare"
          phx-value-id={@kit.id}
          class={[
            "ml-auto shrink-0 rounded-md border px-3 py-1.5 font-mono text-[11px] transition",
            @selected && "border-transparent",
            !@selected && "border-line text-soft hover:border-ink hover:text-ink"
          ]}
          style={@selected && "background-color: #{@color}; color: #{Color.readable_on(@color)}"}
          aria-pressed={to_string(@selected)}
        >
          {if @selected, do: "Im Vergleich", else: "Vergleichen"}
        </button>
      </div>
    </div>
    """
  end

  ## Vergleichs-Modal

  attr :compare_ids, :list, required: true
  attr :kits_by_id, :map, required: true
  attr :season, :string, required: true
  attr :close_path, :string, required: true

  defp compare_modal(assigns) do
    assigns = assign(assigns, :entries, Enum.map(assigns.compare_ids, &assigns.kits_by_id[&1]))

    ~H"""
    <.modal id="compare-modal" close_path={@close_path} label="Direktvergleich" size="max-w-6xl">
      <div class="border-b border-line px-6 py-5">
        <p class="kr-eyebrow">Saison {@season}</p>
        <h2 class="kr-display mt-1.5 text-2xl">Direktvergleich</h2>
        <p class="mt-1 text-sm text-soft">
          {length(@entries)} Trikots nebeneinander. Die Zeilen liegen auf einer Höhe, damit
          sich Verein, Typ und Shop direkt gegenüberstehen.
        </p>
      </div>

      <div :if={@entries == []} class="px-6 py-16 text-center">
        <p class="text-sm text-soft">
          Noch nichts ausgewählt. Tipp in der Übersicht auf „Vergleich“ bei zwei oder drei Trikots.
        </p>
      </div>

      <div :if={@entries != []} class="overflow-x-auto px-6 py-6">
        <div
          class="grid min-w-[560px] gap-x-4"
          style={"grid-template-columns: 5.5rem repeat(#{length(@entries)}, minmax(0, 1fr))"}
        >
          <div></div>
          <div :for={entry <- @entries} class="pb-3">
            <div
              class="flex aspect-[4/5] items-center justify-center rounded-lg p-6"
              style={"background-color: color-mix(in oklab, #{Color.team_color(entry.team)} 14%, #FFFFFF)"}
            >
              <.kit_figure kit={entry.kit} team={entry.team} class="h-full w-full" />
            </div>
          </div>

          <.compare_row label="Verein" entries={@entries} first?>
            <:cell :let={entry}>
              <span class="font-medium">{entry.team.name}</span>
              <span
                class="ml-1.5 font-mono text-[11px] font-semibold"
                style={"color: #{Color.team_color(entry.team)}"}
              >
                {entry.team.short_code}
              </span>
            </:cell>
          </.compare_row>

          <.compare_row label="Trikot" entries={@entries}>
            <:cell :let={entry}>{Kit.label(entry.kit.kit_type)}</:cell>
          </.compare_row>

          <.compare_row label="Liga" entries={@entries}>
            <:cell :let={entry}>{entry.competition.name}</:cell>
          </.compare_row>

          <.compare_row label="Shop" entries={@entries}>
            <:cell :let={entry}>
              <a
                :if={entry.kit.source_shop_url}
                href={entry.kit.source_shop_url}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-1 underline underline-offset-4 hover:opacity-70"
              >
                Ansehen <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
              </a>
              <span :if={!entry.kit.source_shop_url} class="text-soft">—</span>
            </:cell>
          </.compare_row>

          <div class="pt-4"></div>
          <div :for={entry <- @entries} class="pt-4">
            <button
              type="button"
              phx-click="toggle_compare"
              phx-value-id={entry.kit.id}
              class="w-full rounded-md border border-line px-3 py-2 font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
            >
              Herausnehmen
            </button>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  attr :label, :string, required: true
  attr :entries, :list, required: true
  attr :first?, :boolean, default: false
  slot :cell, required: true

  defp compare_row(assigns) do
    ~H"""
    <div class={["kr-eyebrow py-3", !@first? && "border-t border-line"]}>{@label}</div>
    <div
      :for={entry <- @entries}
      class={["py-3 text-sm", !@first? && "border-t border-line"]}
    >
      {render_slot(@cell, entry)}
    </div>
    """
  end
end
