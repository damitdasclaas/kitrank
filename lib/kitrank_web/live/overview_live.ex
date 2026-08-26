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
  alias KitrankWeb.KitLabel

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
      |> assign_back(params)
      |> assign_open_team(params)
      |> assign_page_title()

    {:noreply, socket}
  end

  ## Events

  @impl true
  def handle_event("select_season", %{"season" => season}, socket) do
    # Beim Saisonwechsel fällt die Auswahl weg – sie zeigt auf Trikots, die es
    # in der neuen Saison so nicht gibt. Die einzeln umgeschalteten Kacheln
    # ebenso: welche Varianten ein Verein hat, ist von Saison zu Saison anders.
    {:noreply,
     socket
     |> load_season(season)
     |> assign(:tile_kit, %{})
     |> push_patch(to: ~p"/")}
  end

  def handle_event("toggle_league", %{"id" => id}, socket) do
    id = String.to_integer(id)

    # Nochmal auf die offene Liga klappt sie zu – das erwartet man von einer
    # Ueberschrift, die sich wie ein Schalter verhaelt.
    offen = if socket.assigns.open_league == id, do: nil, else: id

    {:noreply, assign(socket, :open_league, offen)}
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
           gettext("Im Vergleich haben drei Trikots Platz. Nimm erst eins heraus.")
         )}

      true ->
        {:noreply, patch_compare(socket, selected ++ [id])}
    end
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_visible()}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, socket |> assign(:query, "") |> assign_visible()}
  end

  # Nochmal auf die aktive Sortierung dreht sie um – das erwartet man von einer
  # Spaltenueberschrift, und es spart einen zweiten Satz Knoepfe fuer die
  # Richtung. Ein Wechsel des Schluessels faengt bei dessen natuerlicher
  # Richtung an: Namen von A an, Trikots mit den meisten zuerst.
  def handle_event("sort_teams", %{"by" => by}, socket) do
    by = sort_key_from(by)

    {sort, dir} =
      if by == socket.assigns.sort do
        {by, if(socket.assigns.sort_dir == :asc, do: :desc, else: :asc)}
      else
        {by, default_dir(by)}
      end

    {:noreply, socket |> assign(sort: sort, sort_dir: dir) |> assign_visible()}
  end

  # Eine Kachel umschalten. Die Wahl gilt nur fuer diesen Verein und ueberstimmt
  # die globale – wer bei einem Verein das Auswaertstrikot sehen will, will
  # deshalb nicht ueberall Auswaerts.
  def handle_event("show_kit", %{"team" => team_id, "type" => kit_type}, socket) do
    tile_kit = Map.put(socket.assigns.tile_kit, String.to_integer(team_id), kit_type)
    {:noreply, assign(socket, :tile_kit, tile_kit)}
  end

  # Alle auf einmal. Das raeumt die einzelnen Wahlen weg: „alle auf Auswaerts"
  # heisst alle, sonst blieben vorher angetippte Kacheln stehen und die Ansicht
  # waere gemischt, ohne dass man sieht warum.
  def handle_event("show_all_kits", %{"type" => kit_type}, socket) do
    {:noreply, assign(socket, kit_view: kit_type, tile_kit: %{})}
  end

  def handle_event("select_image", %{"kit-id" => kit_id, "index" => index}, socket) do
    choices = Map.put(socket.assigns.image_choice, kit_id, String.to_integer(index))
    {:noreply, assign(socket, :image_choice, choices)}
  end

  # Startet dort, wo die kleine Ansicht gerade steht – wer Bild 2 anschaut und
  # vergroessert, will Bild 2 gross sehen, nicht wieder Bild 1.
  def handle_event("zoom", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Map.get(socket.assigns.kits_by_id, id) do
      nil ->
        {:noreply, socket}

      entry ->
        {:noreply, assign(socket, :zoom, %{kit_id: id, index: current_index(socket, entry)})}
    end
  end

  def handle_event("zoom_close", _params, socket), do: {:noreply, assign(socket, :zoom, nil)}

  def handle_event("zoom_step", %{"delta" => delta}, socket) do
    {:noreply, step_zoom(socket, String.to_integer(delta))}
  end

  def handle_event("zoom_key", %{"key" => key}, socket) do
    case key do
      "Escape" -> {:noreply, assign(socket, :zoom, nil)}
      "ArrowLeft" -> {:noreply, step_zoom(socket, -1)}
      "ArrowRight" -> {:noreply, step_zoom(socket, 1)}
      _ -> {:noreply, socket}
    end
  end

  # Klick aufs Bild selbst soll die grosse Ansicht nicht schliessen.
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  defp current_index(socket, entry) do
    count = entry.kit |> kit_images() |> length()
    index = Map.get(socket.assigns.image_choice, to_string(entry.kit.id), 0)

    if index < count, do: index, else: 0
  end

  defp step_zoom(%{assigns: %{zoom: nil}} = socket, _delta), do: socket

  defp step_zoom(%{assigns: %{zoom: zoom}} = socket, delta) do
    entry = socket.assigns.kits_by_id[zoom.kit_id]
    count = entry.kit |> kit_images() |> length()

    if count <= 1 do
      socket
    else
      index = Integer.mod(zoom.index + delta, count)

      socket
      |> assign(:zoom, %{zoom | index: index})
      # Die kleine Ansicht zieht mit, damit nach dem Schliessen dasselbe Bild steht.
      |> assign(
        :image_choice,
        Map.put(socket.assigns.image_choice, to_string(zoom.kit_id), index)
      )
    end
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
      kit_count: map_size(kits_by_id),
      kit_types: available_kit_types(overview)
    )
    |> assign_new(:image_choice, fn -> %{} end)
    |> assign_new(:zoom, fn -> nil end)
    |> assign_new(:compare_ids, fn -> [] end)
    |> assign_new(:back, fn -> nil end)
    |> assign_new(:kit_view, fn -> "home" end)
    |> assign_new(:tile_kit, fn -> %{} end)
    |> assign_new(:query, fn -> "" end)
    |> assign_new(:sort, fn -> :name end)
    |> assign_new(:sort_dir, fn -> :asc end)
    |> assign_visible()
    |> assign_new(:open_team, fn -> nil end)
    |> open_first_league()
  end

  # Was das Raster tatsaechlich zeigt: die geladene Uebersicht, durch Suche und
  # Sortierung geschickt. Als Assign und nicht im Render, damit es einmal pro
  # Aenderung passiert statt einmal pro Durchlauf.
  defp assign_visible(socket) do
    sichtbar =
      socket.assigns.overview
      |> filter_overview(socket.assigns.query)
      |> sort_overview(socket.assigns.sort, socket.assigns.sort_dir)

    assign(socket,
      visible: sichtbar,
      visible_team_count: Enum.sum(Enum.map(sichtbar, fn {_c, teams} -> length(teams) end))
    )
  end

  ## Suche

  defp filter_overview(overview, query) when query in [nil, ""], do: overview

  defp filter_overview(overview, query) do
    gesucht = suchform(query)

    overview
    |> Enum.map(fn {competition, teams} ->
      # Trifft der Ligenname, gehoert die ganze Liga zum Ergebnis – "Bundesliga"
      # einzutippen und dann keinen einzigen Verein zu sehen waere seltsam.
      if String.contains?(suchform(competition.name), gesucht) do
        {competition, teams}
      else
        {competition, Enum.filter(teams, fn {team, _kits} -> trifft?(team, gesucht) end)}
      end
    end)
    |> Enum.reject(fn {_competition, teams} -> teams == [] end)
  end

  defp trifft?(team, gesucht) do
    String.contains?(suchform(team.name), gesucht) or
      String.contains?(suchform(team.short_code), gesucht)
  end

  # Kleinschreibung reicht bei deutschen Vereinsnamen nicht: wer "koln" tippt,
  # meint Köln, und wer "fussball" tippt, meint Fußball. Akzente werden
  # abgetrennt (NFD) und weggeworfen, ß wird zu ss.
  defp suchform(text) do
    text
    |> String.downcase()
    |> String.replace("ß", "ss")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.trim()
  end

  ## Sortierung der Vereine – innerhalb ihrer Liga, die Ligen bleiben, wie sie sind

  defp sort_overview(overview, sort, dir) do
    Enum.map(overview, fn {competition, teams} ->
      # Erst nach Namen, dann nach dem eigentlichen Schluessel: Enum.sort_by ist
      # stabil, also stehen Vereine mit gleich vielen Trikots alphabetisch.
      sortiert =
        teams
        |> Enum.sort_by(fn {team, _kits} -> suchform(team.name) end)
        |> Enum.sort_by(&sort_value(&1, sort), dir)

      {competition, sortiert}
    end)
  end

  defp sort_value({team, _kits}, :name), do: suchform(team.name)
  defp sort_value({team, _kits}, :code), do: team.short_code
  defp sort_value({_team, kits}, :kits), do: length(kits)

  defp sort_key_from("code"), do: :code
  defp sort_key_from("kits"), do: :kits
  defp sort_key_from(_), do: :name

  defp default_dir(:kits), do: :desc
  defp default_dir(_), do: :asc

  defp sort_label(:name), do: gettext("Name")
  defp sort_label(:code), do: gettext("Kürzel")
  defp sort_label(:kits), do: gettext("Trikots")

  # Nur die Typen, die es in dieser Saison wirklich gibt – ein Schalter fuer
  # „Sonder", wenn kein Verein ein Sondertrikot hat, taete nichts.
  defp available_kit_types(overview) do
    vorhanden =
      for {_competition, teams} <- overview,
          {_team, kits} <- teams,
          kit <- kits,
          into: MapSet.new(),
          do: kit.kit_type

    Enum.filter(Kit.kit_types(), &MapSet.member?(vorhanden, &1))
  end

  # Beim Laden und nach einem Saisonwechsel die oberste Liga aufklappen – bei
  # zwei deutschen Ligen also die Bundesliga. Offen ist immer hoechstens eine;
  # ein Klick auf eine andere klappt die vorige zu.
  defp open_first_league(socket) do
    erste =
      case socket.assigns.overview do
        [{competition, _teams} | _] -> competition.id
        [] -> nil
      end

    assign(socket, :open_league, erste)
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

  # Woher das Detail aufgerufen wurde. Ohne diese Spur landet man beim
  # Schliessen auf der Uebersicht, obwohl man aus dem Vergleich kam – und muss
  # den Vergleich neu aufmachen, um beim naechsten Trikot dasselbe zu tun.
  defp assign_back(socket, params) do
    assign(socket, :back, if(params["zurueck"] == "vergleich", do: "vergleich"))
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
        {:compare, _} -> gettext("Direktvergleich")
        _ -> gettext("Übersicht")
      end

    assign(socket, :page_title, title)
  end

  defp patch_compare(socket, ids) do
    push_patch(socket,
      to: path_for(socket.assigns.live_action, socket.assigns.open_team, ids, socket.assigns.back)
    )
  end

  ## Pfade – die Auswahl reist über alle Ansichten mit

  defp path_for(action, open_team, ids, back \\ nil) do
    query = if ids == [], do: %{}, else: %{"trikots" => Enum.join(ids, ",")}
    query = if back, do: Map.put(query, "zurueck", back), else: query

    case {action, open_team} do
      {:team, %{team: team}} -> ~p"/teams/#{team.id}?#{query}"
      {:compare, _} -> ~p"/vergleich?#{query}"
      _ -> ~p"/?#{query}"
    end
  end

  defp index_path(ids), do: path_for(:index, nil, ids)
  defp compare_path(ids), do: path_for(:compare, nil, ids)
  defp team_path(team, ids, back \\ nil), do: path_for(:team, %{team: team}, ids, back)

  # Der Weg zurueck aus dem Detail: in den Vergleich, wenn es von dort kam.
  # Steht dort inzwischen nur noch ein Trikot, waere der Vergleich leer – dann
  # doch die Uebersicht.
  defp close_detail_path("vergleich", ids) when length(ids) >= 2, do: compare_path(ids)
  defp close_detail_path(_back, ids), do: index_path(ids)

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-[1500px] px-4 pb-32 pt-10 sm:px-6 lg:px-8">
        <.page_intro
          season={@season}
          seasons={@seasons}
          kit_count={@kit_count}
          team_count={map_size(@teams_by_id)}
          kit_types={@kit_types}
          kit_view={@kit_view}
          tile_kit={@tile_kit}
        />

        <.browse_controls
          query={@query}
          sort={@sort}
          sort_dir={@sort_dir}
          result_count={@visible_team_count}
        />

        <div
          :if={@overview == []}
          class="mt-16 rounded-lg border border-dashed border-line p-12 text-center"
        >
          <p class="kr-display text-xl">
            {gettext("Noch keine Trikots für %{saison}", saison: @season)}
          </p>
          <p class="mx-auto mt-2 max-w-md text-sm text-soft">
            {gettext("Trag Ligen, Teams und Trikots im Admin ein — dann füllt sich diese Seite.")}
          </p>
        </div>

        <div
          :if={@overview != [] && @visible == []}
          class="mt-16 rounded-lg border border-dashed border-line p-12 text-center"
        >
          <p class="kr-display text-xl">
            {gettext("Nichts gefunden für „%{suche}“", suche: @query)}
          </p>
          <p class="mx-auto mt-2 max-w-md text-sm text-soft">
            {gettext("Such nach Verein, Kürzel oder Liga — „BVB“ und „dortmund“ führen zum selben.")}
          </p>
          <button
            type="button"
            phx-click="clear_search"
            class="mt-5 rounded-md border border-line px-4 py-2 text-sm transition hover:border-ink"
          >{gettext("Suche zurücksetzen")}</button>
        </div>

        <section :for={{competition, teams} <- @visible} class="mt-10 first:mt-8">
          <.league_header
            competition={competition}
            team_count={length(teams)}
            open?={league_open?(@open_league, @query, competition)}
          />

          <div
            :if={league_open?(@open_league, @query, competition)}
            id={"liga-#{competition.id}"}
            class="kr-rise mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6"
          >
            <.team_tile
              :for={{team, kits} <- teams}
              team={team}
              kits={kits}
              compare_ids={@compare_ids}
              shown={Map.get(@tile_kit, team.id, @kit_view)}
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
        close_path={close_detail_path(@back, @compare_ids)}
        zoomed?={@zoom != nil}
      />

      <.compare_modal
        :if={@live_action == :compare}
        compare_ids={@compare_ids}
        kits_by_id={@kits_by_id}
        season={@season}
        close_path={index_path(@compare_ids)}
        zoomed?={@zoom != nil}
      />

      <.kit_lightbox
        :if={@zoom}
        kit={@kits_by_id[@zoom.kit_id].kit}
        team={@kits_by_id[@zoom.kit_id].team}
        images={kit_images(@kits_by_id[@zoom.kit_id].kit)}
        index={@zoom.index}
        label={KitLabel.display(@kits_by_id[@zoom.kit_id].kit)}
      />
    </Layouts.app>
    """
  end

  ## Seitenkopf

  attr :season, :string, required: true
  attr :seasons, :list, required: true
  attr :kit_count, :integer, required: true
  attr :team_count, :integer, required: true
  attr :kit_types, :list, required: true
  attr :kit_view, :string, required: true
  attr :tile_kit, :map, required: true

  defp page_intro(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 border-b border-line pb-8 md:flex-row md:items-end md:justify-between">
      <div>
        <p class="kr-eyebrow">{gettext("Saison %{jahr}", jahr: @season)}</p>
        <%!-- Die Frage, um die es geht – und nicht der Name der Ligen, die
              gerade in der Datenbank stehen.

              Ein Satz, keine zwei Meldungen: der Umbruch war vorher ein <br/>
              mitten im Satz, und wohin er in einer anderen Sprache gehoert,
              kann die Uebersetzung nicht entscheiden. Das macht jetzt
              text-wrap: balance. --%>
        <h1 class="kr-display mt-2 max-w-[14ch] text-4xl leading-[0.95] text-balance sm:text-5xl">
          {gettext("Welches Trikot ist das schönste?")}
        </h1>
        <p class="mt-4 max-w-md text-sm leading-relaxed text-soft">
          {gettext(
            "%{trikots} Trikots von %{vereine} Vereinen. Verein antippen für alle Varianten, zwei bis drei nebeneinanderlegen — oder gleich",
            trikots: @kit_count,
            vereine: @team_count
          )}
          <.link navigate={~p"/rankings/new"} class="text-ink underline underline-offset-4">
            {gettext("eine eigene Rangliste bauen")}
          </.link>.
        </p>
      </div>

      <div class="flex flex-col gap-3 md:items-end">
        <%!-- Alle Kacheln auf einmal. Einzeln geht es ueber die Kuerzel auf
              der Kachel selbst – das ist der haeufigere Fall, deshalb steht
              es dort und nicht hier. --%>
        <div :if={length(@kit_types) > 1} class="flex items-center gap-2">
          <span class="kr-eyebrow">{gettext("Trikot")}</span>
          <div class="flex gap-1 rounded-lg border border-line bg-sunk p-1">
            <button
              :for={kit_type <- @kit_types}
              type="button"
              phx-click="show_all_kits"
              phx-value-type={kit_type}
              data-role="show-all-kits"
              class={[
                "rounded-md px-2.5 py-1.5 font-mono text-xs transition",
                kit_type == @kit_view && @tile_kit == %{} && "bg-panel text-ink shadow-sm",
                (kit_type != @kit_view || @tile_kit != %{}) && "text-soft hover:text-ink"
              ]}
              aria-pressed={to_string(kit_type == @kit_view && @tile_kit == %{})}
              title={KitLabel.label(kit_type)}
            >
              {KitLabel.label(kit_type)}
            </button>
          </div>
        </div>

        <div :if={length(@seasons) > 1} class="flex items-center gap-2">
          <span class="kr-eyebrow">{gettext("Saison")}</span>
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
    </div>
    """
  end

  # Waehrend einer Suche sind alle Treffer-Ligen offen. Sonst faende man etwas
  # und saehe es nicht, weil es in einer zugeklappten Liga steht.
  defp league_open?(_open_league, query, _competition) when query not in [nil, ""], do: true
  defp league_open?(open_league, _query, competition), do: open_league == competition.id

  ## Suchen und Sortieren

  attr :query, :string, required: true
  attr :sort, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :result_count, :integer, required: true

  # Unter der Trennlinie statt darueber: oben steht, worum es geht, hier steht,
  # was man damit tun kann.
  defp browse_controls(assigns) do
    ~H"""
    <div class="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center">
      <form id="verein-suche" phx-change="search" class="relative w-full sm:max-w-xs">
        <.icon
          name="hero-magnifying-glass-mini"
          class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-soft"
        />
        <input
          type="search"
          name="q"
          value={@query}
          phx-debounce="200"
          autocomplete="off"
          placeholder={gettext("Verein, Kürzel oder Liga")}
          aria-label={gettext("Vereine durchsuchen")}
          class="w-full rounded-lg border border-line bg-panel py-2 pl-9 pr-9 text-sm placeholder:text-soft/70 focus:border-ink focus:outline-none"
        />
        <%!-- type="search" bringt in manchen Browsern ein eigenes Kreuz mit, in
              anderen keins. Ein eigenes ist ueberall da und loest das Ereignis
              aus, das den Zustand wirklich zuruecksetzt. --%>
        <button
          :if={@query != ""}
          type="button"
          phx-click="clear_search"
          data-role="clear-search"
          class="absolute right-2 top-1/2 flex size-6 -translate-y-1/2 items-center justify-center rounded-full text-soft transition hover:text-ink"
          aria-label={gettext("Suche zurücksetzen")}
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </form>

      <p :if={@query != ""} class="font-mono text-[11px] text-soft" aria-live="polite">
        {ngettext("%{anzahl} Verein", "%{anzahl} Vereine", @result_count, anzahl: @result_count)}
      </p>

      <div class="flex items-center gap-2 sm:ml-auto">
        <span class="kr-eyebrow">{gettext("Sortieren")}</span>
        <div class="flex gap-1 rounded-lg border border-line bg-sunk p-1">
          <button
            :for={key <- [:name, :code, :kits]}
            type="button"
            phx-click="sort_teams"
            phx-value-by={key}
            data-role="sort-teams"
            class={[
              "flex items-center gap-1 rounded-md px-2.5 py-1.5 font-mono text-xs transition",
              key == @sort && "bg-panel text-ink shadow-sm",
              key != @sort && "text-soft hover:text-ink"
            ]}
            aria-pressed={to_string(key == @sort)}
          >
            {sort_label(key)}
            <.icon
              :if={key == @sort}
              name={if @sort_dir == :asc, do: "hero-arrow-up-mini", else: "hero-arrow-down-mini"}
              class="size-3"
            />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :competition, :map, required: true
  attr :team_count, :integer, required: true
  attr :open?, :boolean, required: true

  # Die Ueberschrift ist der Schalter. Offen ist hoechstens eine Liga; ein Klick
  # auf die offene klappt sie zu – das erwartet man von einem Schalter, und die
  # Kopfzeile bleibt sichtbar, die Seite wirkt also nicht leer.
  defp league_header(assigns) do
    ~H"""
    <h2 class="border-b border-line">
      <button
        type="button"
        phx-click="toggle_league"
        phx-value-id={@competition.id}
        aria-expanded={to_string(@open?)}
        aria-controls={"liga-#{@competition.id}"}
        class="flex w-full items-center gap-3 pb-2 text-left transition hover:opacity-80"
      >
        <.icon
          name={if @open?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-5 shrink-0 text-soft"
        />
        <span class="kr-display text-xl leading-none">{@competition.name}</span>
        <span class="kr-eyebrow">
          {gettext("%{land} · Liga %{stufe}",
            land: @competition.country,
            stufe: @competition.tier
          )}
        </span>
        <span class="ml-auto shrink-0 font-mono text-xs text-soft">
          {gettext("%{anzahl} Vereine", anzahl: @team_count)}
        </span>
      </button>
    </h2>
    """
  end

  ## Team-Kachel

  attr :team, :map, required: true
  attr :kits, :list, required: true
  attr :compare_ids, :list, required: true
  attr :href, :string, required: true

  attr :shown, :string,
    required: true,
    doc: "gewuenschter Trikot-Typ; hat der Verein ihn nicht, bleibt es beim Heimtrikot"

  defp team_tile(assigns) do
    assigns =
      assigns
      |> assign(:color, Color.team_color(assigns.team))
      |> assign(:lead_kit, shown_kit(assigns.kits, assigns.shown))

    ~H"""
    <div class="group relative overflow-hidden rounded-lg border border-line bg-panel transition hover:border-ink/25 hover:shadow-[0_8px_28px_-16px_rgb(0_0_0/0.45)]">
      <%!-- Die Bühne bleibt in beiden Themes hell: Trikots sind Produktfotos,
            und die liegen auf Weiß. --%>
      <div
        class="relative flex aspect-[4/3] items-center justify-center overflow-hidden px-6 py-4"
        style={"background-color: color-mix(in oklab, #{@color} 15%, #FFFFFF)"}
      >
        <.kit_figure
          :if={@lead_kit}
          kit={@lead_kit}
          team={@team}
          fill
          class="transition-transform duration-300 group-hover:-translate-y-1"
          size={:thumb}
        />
        <span :if={!@lead_kit} class="font-mono text-[11px] text-black/40">{gettext("kein Trikot")}</span>

        <button
          :if={@lead_kit}
          type="button"
          phx-click="toggle_compare"
          phx-value-id={@lead_kit.id}
          data-role="tile-compare"
          class={
            [
              "absolute right-2 top-2 z-20 flex h-7 items-center gap-1 rounded-full border px-2",
              "font-mono text-[10px] font-medium transition",
              @lead_kit.id in @compare_ids && "border-transparent text-white",
              # Auf dem Handy gibt es kein Hover: was nur beim Zeigen erscheint,
              # existiert dort nicht. Deshalb sichtbar — und erst ab sm, wo eine
              # Maus wahrscheinlich ist, zurueckhaltend.
              @lead_kit.id not in @compare_ids &&
                "border-black/10 bg-white/85 text-black/60 backdrop-blur sm:opacity-0 sm:focus-visible:opacity-100 sm:group-hover:opacity-100"
            ]
          }
          style={
            @lead_kit.id in @compare_ids &&
              "background-color: #{@color}; color: #{Color.readable_on(@color)}"
          }
          aria-pressed={to_string(@lead_kit.id in @compare_ids)}
          aria-label={
            if @lead_kit.id in @compare_ids,
              do:
                gettext("%{verein} %{trikot} aus dem Vergleich nehmen",
                  verein: @team.name,
                  trikot: KitLabel.display(@lead_kit)
                ),
              else:
                gettext("%{verein} %{trikot} vergleichen",
                  verein: @team.name,
                  trikot: KitLabel.display(@lead_kit)
                )
          }
        >
          <.icon
            name={if @lead_kit.id in @compare_ids, do: "hero-check-mini", else: "hero-plus-mini"}
            class="size-3"
          />
          {if @lead_kit.id in @compare_ids, do: gettext("Drin"), else: gettext("Vergleich")}
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
        <%!-- Ueber dem Kachel-Link, sonst faengt der die Klicks ab. --%>
        <span class="relative z-20 ml-auto flex shrink-0 gap-1">
          <button
            :for={kit <- @kits}
            type="button"
            phx-click="show_kit"
            phx-value-team={@team.id}
            phx-value-type={kit.kit_type}
            data-role="tile-kit"
            aria-pressed={to_string(@lead_kit && kit.id == @lead_kit.id)}
            aria-label={
              gettext("%{verein}: %{trikot} zeigen",
                verein: @team.name,
                trikot: KitLabel.label(kit.kit_type)
              )
            }
            class="rounded-[3px] transition hover:opacity-80"
          >
            <.kit_badge
              kit_type={kit.kit_type}
              class={
                if @lead_kit && kit.id == @lead_kit.id,
                  do: "text-white",
                  else: "bg-sunk text-soft"
              }
              style={
                @lead_kit && kit.id == @lead_kit.id &&
                  "background-color: #{@color}; color: #{Color.readable_on(@color)}"
              }
            />
          </button>
        </span>
      </div>

      <%!-- Liegt unter den echten Buttons, deckt aber die ganze Kachel ab. --%>
      <.link
        patch={@href}
        class="absolute inset-0 z-10"
        aria-label={gettext("%{verein} — alle Trikots", verein: @team.name)}
      >
        <span class="sr-only">{@team.name}</span>
      </.link>
    </div>
    """
  end

  defp lead_kit(kits) do
    Enum.find(kits, &(&1.kit_type == "home")) || List.first(kits)
  end

  # Faellt auf das Heimtrikot zurueck, statt die Kachel leer zu lassen: nicht
  # jeder Verein hat ein Ausweich- oder Sondertrikot, und „alle auf Ausweich"
  # soll keine Luecken ins Raster reissen.
  defp shown_kit(kits, kit_type) do
    Enum.find(kits, &(&1.kit_type == kit_type)) || lead_kit(kits)
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
        <span class="kr-eyebrow hidden shrink-0 sm:block">{gettext("Vergleich")}</span>

        <ul class="flex flex-1 items-center gap-2 overflow-x-auto">
          <li :for={id <- @compare_ids} class="shrink-0">
            <.tray_chip entry={@kits_by_id[id]} />
          </li>
          <li :if={length(@compare_ids) < 3} class="shrink-0 font-mono text-[11px] text-soft">
            {gettext("noch %{anzahl} möglich", anzahl: 3 - length(@compare_ids))}
          </li>
        </ul>

        <.link
          patch={@clear_path}
          class="shrink-0 font-mono text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
        >{gettext("Leeren")}</.link>

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
        >{gettext("noch eins dazu")}</span>
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
        <.kit_figure kit={@entry.kit} team={@entry.team} class="h-4 w-4" size={:thumb} />
      </span>
      <span class="font-mono text-[11px] font-semibold" style={"color: #{@color}"}>
        {@entry.team.short_code}
      </span>
      <span class="text-[11px] text-soft">{KitLabel.display(@entry.kit)}</span>
      <button
        type="button"
        phx-click="toggle_compare"
        phx-value-id={@entry.kit.id}
        data-role="tray-remove"
        class="text-soft transition hover:text-ink"
        aria-label={
          gettext("%{verein} %{trikot} aus dem Vergleich nehmen",
            verein: @entry.team.name,
            trikot: KitLabel.display(@entry.kit)
          )
        }
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
  attr :zoomed?, :boolean, default: false

  defp team_modal(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.entry.team))

    ~H"""
    <.modal
      id="team-modal"
      close_path={@close_path}
      label={gettext("Trikots von %{verein}", verein: @entry.team.name)}
      size="max-w-5xl"
      close_on_escape={!@zoomed?}
    >
      <div
        class="border-b border-line px-6 py-5"
        style={"background-color: color-mix(in oklab, #{@color} 8%, transparent)"}
      >
        <p class="kr-eyebrow">
          {gettext("%{liga} · Saison %{saison}", liga: @entry.competition.name, saison: @season)}
        </p>
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
          {gettext("Vereinsshop")} <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
        </a>
      </div>

      <div :if={@entry.kits == []} class="px-6 py-12 text-center">
        <p class="text-sm text-soft">
          {gettext("Für %{verein} sind in %{saison} noch keine Trikots hinterlegt.",
            verein: @entry.team.name,
            saison: @season
          )}
        </p>
      </div>

      <%!-- Zwei Spalten schon auf dem Handy, wie im Raster der Startseite.
            Mit einer Spalte war die Bildflaeche auf einem 390er Display 302 px
            gross — mehr als die 192 px am Rechner. Das Detail war damit auf dem
            kleinen Geraet groesser als auf dem grossen. --%>
      <div class="grid grid-cols-2 gap-px bg-line lg:grid-cols-3">
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
      <button
        type="button"
        phx-click="zoom"
        phx-value-id={@kit.id}
        class="group relative flex aspect-square cursor-zoom-in items-center justify-center overflow-hidden p-4 sm:p-8"
        style={"background-color: color-mix(in oklab, #{@color} 13%, #FFFFFF)"}
        aria-label={
          gettext("%{verein} %{trikot} groß ansehen",
            verein: @team.name,
            trikot: KitLabel.display(@kit)
          )
        }
      >
        <.kit_figure
          kit={@kit}
          team={@team}
          image_url={@active_image}
          fill
          class="transition-transform duration-300 group-hover:scale-[1.04]"
        />
        <.zoom_hint />
      </button>

      <div :if={length(@images) > 1} class="border-t border-line px-3 py-2.5">
        <.kit_thumbstrip
          kit={@kit}
          team={@team}
          images={@images}
          index={@active_index}
          event="select_image"
          extra={%{kit_id: @kit.id}}
        />
      </div>

      <div class="flex flex-col items-start gap-2 border-t border-line px-4 py-3 sm:flex-row sm:items-center">
        <div class="min-w-0">
          <p class="text-sm font-medium">{KitLabel.display(@kit)}</p>
          <a
            :if={@kit.source_shop_url}
            href={@kit.source_shop_url}
            target="_blank"
            rel="noopener noreferrer"
            class="mt-0.5 inline-flex items-center gap-1 text-[11px] text-soft underline underline-offset-4 hover:text-ink"
          >
            {gettext("Zum Vereinsshop")}
            <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
          </a>
          <p :if={!@kit.source_shop_url} class="mt-0.5 text-[11px] text-soft">
            {gettext("Kein Shop-Link hinterlegt")}
          </p>
        </div>

        <button
          type="button"
          phx-click="toggle_compare"
          phx-value-id={@kit.id}
          class={[
            "shrink-0 rounded-md border px-3 py-1.5 font-mono text-[11px] transition sm:ml-auto",
            @selected && "border-transparent",
            !@selected && "border-line text-soft hover:border-ink hover:text-ink"
          ]}
          style={@selected && "background-color: #{@color}; color: #{Color.readable_on(@color)}"}
          aria-pressed={to_string(@selected)}
        >
          {if @selected, do: gettext("Im Vergleich"), else: gettext("Vergleichen")}
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
  attr :zoomed?, :boolean, default: false

  defp compare_modal(assigns) do
    assigns = assign(assigns, :entries, Enum.map(assigns.compare_ids, &assigns.kits_by_id[&1]))

    ~H"""
    <.modal
      id="compare-modal"
      close_path={@close_path}
      label="Direktvergleich"
      size="max-w-6xl"
      close_on_escape={!@zoomed?}
      full_on_mobile
    >
      <%!-- Auf dem Handy fuellt der Vergleich den Bildschirm: die Bilder
            bekommen den Rest der Hoehe, der Rest nur so viel, wie er braucht.
            Ab sm ist es wieder eine Karte im Fluss. --%>
      <div class="flex min-h-[100dvh] flex-col sm:block sm:min-h-0">
        <div class="shrink-0 border-b border-line px-4 py-4 sm:px-6 sm:py-5">
          <p class="kr-eyebrow">{gettext("Saison %{jahr}", jahr: @season)}</p>
          <h2 class="kr-display mt-1.5 text-xl sm:text-2xl">{gettext("Direktvergleich")}</h2>
          <p class="mt-1 hidden text-sm text-soft sm:block">
            {gettext(
              "%{anzahl} Trikots nebeneinander. Die Zeilen liegen auf einer Höhe, damit sich Verein, Typ und Shop direkt gegenüberstehen.",
              anzahl: length(@entries)
            )}
          </p>
        </div>

        <div :if={@entries == []} class="px-6 py-16 text-center">
          <p class="text-sm text-soft">
            {gettext(
              "Noch nichts ausgewählt. Tipp in der Übersicht auf „Vergleich“ bei zwei oder drei Trikots."
            )}
          </p>
        </div>

        <.compare_columns :if={@entries != []} entries={@entries} />

        <div :if={@entries != []} class="hidden overflow-x-auto px-6 py-6 sm:block">
          <div
            class="grid min-w-[560px] gap-x-4"
            style={"grid-template-columns: 5.5rem repeat(#{length(@entries)}, minmax(0, 1fr))"}
          >
            <div></div>
            <div :for={entry <- @entries} class="pb-3">
              <button
                type="button"
                phx-click="zoom"
                phx-value-id={entry.kit.id}
                data-role="compare-zoom"
                class="group relative flex aspect-[4/5] w-full cursor-zoom-in items-center justify-center rounded-lg p-6"
                style={"background-color: color-mix(in oklab, #{Color.team_color(entry.team)} 14%, #FFFFFF)"}
                aria-label={
                  gettext("%{verein} %{trikot} groß ansehen",
                    verein: entry.team.name,
                    trikot: KitLabel.display(entry.kit)
                  )
                }
              >
                <.kit_figure
                  kit={entry.kit}
                  team={entry.team}
                  fill
                  class="transition-transform duration-300 group-hover:scale-[1.04]"
                />
                <.zoom_hint />
              </button>
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
              <:cell :let={entry}>{KitLabel.display(entry.kit)}</:cell>
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
                  {gettext("Vereinsshop")}
                  <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
                </a>
                <span :if={!entry.kit.source_shop_url} class="text-soft">—</span>
              </:cell>
            </.compare_row>

            <div class="pt-4"></div>
            <div :for={entry <- @entries} class="flex gap-2 pt-4">
              <.link
                patch={team_path(entry.team, @compare_ids, "vergleich")}
                data-role="compare-detail"
                class="flex-1 rounded-md border border-line px-3 py-2 text-center font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
              >{gettext("Detail")}</.link>
              <button
                type="button"
                phx-click="toggle_compare"
                phx-value-id={entry.kit.id}
                class="flex-1 rounded-md border border-line px-3 py-2 font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
              >{gettext("Herausnehmen")}</button>
            </div>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  attr :entries, :list, required: true

  # Die Handy-Fassung des Vergleichs. Kein zweites Layout aus Bequemlichkeit:
  # die Tabelle daneben braucht eine Beschriftungsspalte und 560 px Breite,
  # damit die Zeilen gegenueberstehen. Auf 390 px heisst das seitlich scrollen —
  # und dann sieht man nie beide Trikots gleichzeitig, was der ganze Zweck ist.
  # Hier steht darum die Beschriftung ueber dem Wert statt daneben.
  defp compare_columns(assigns) do
    ~H"""
    <div
      class="grid min-h-0 flex-1 gap-2 px-3 pb-3 pt-3 sm:hidden"
      style={"grid-template-columns: repeat(#{length(@entries)}, minmax(0, 1fr))"}
    >
      <div :for={entry <- @entries} class="flex min-h-0 flex-col">
        <button
          type="button"
          phx-click="zoom"
          phx-value-id={entry.kit.id}
          data-role="compare-zoom-mobile"
          class="group relative min-h-0 flex-1 overflow-hidden rounded-lg"
          style={"background-color: color-mix(in oklab, #{Color.team_color(entry.team)} 14%, #FFFFFF)"}
          aria-label={
            gettext("%{verein} %{trikot} groß ansehen",
              verein: entry.team.name,
              trikot: KitLabel.display(entry.kit)
            )
          }
        >
          <%!-- Ohne Polster: `fill` misst gegen die Padding-Box, ein p-* am
                Bild bliebe wirkungslos. Hier ist das richtig — im Vergleich
                zaehlt jeder Pixel Trikot. --%>
          <.kit_figure kit={entry.kit} team={entry.team} fill />
        </button>

        <p
          class="mt-2 truncate font-mono text-[11px] font-semibold"
          style={"color: #{Color.team_color(entry.team)}"}
        >
          {entry.team.short_code}
        </p>
        <p class="truncate text-[13px] leading-tight">{entry.team.name}</p>
        <p class="truncate text-[11px] text-soft">{KitLabel.display(entry.kit)}</p>
        <p class="truncate text-[11px] text-soft">{entry.competition.name}</p>

        <.link
          patch={team_path(entry.team, Enum.map(@entries, & &1.kit.id), "vergleich")}
          data-role="compare-detail-mobile"
          class="mt-2 rounded-md border border-line px-2 py-1.5 text-center font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
        >{gettext("Detail")}</.link>

        <button
          type="button"
          phx-click="toggle_compare"
          phx-value-id={entry.kit.id}
          class="mt-1 rounded-md px-2 py-1.5 text-center font-mono text-[11px] text-soft transition hover:text-ink"
        >{gettext("Herausnehmen")}</button>
      </div>
    </div>
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
