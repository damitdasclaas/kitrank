defmodule KitrankWeb.Admin.TeamLive do
  @moduledoc """
  Vereine. Stammdaten, die über Saisons stabil bleiben – die Liga hängt bewusst
  nicht hier, sondern unter „Saison“.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components

  alias Kitrank.Kits
  alias Kitrank.Kits.Team
  alias KitrankWeb.Color
  alias KitrankWeb.Search

  @impl true
  def mount(_params, _session, socket) do
    seasons = seasons_with_data()

    {:ok,
     socket
     |> assign(
       page_title: "Vereine",
       seasons: seasons,
       season: List.first(seasons) || Kits.current_season(),
       search: "",
       league_filter: MapSet.new()
     )
     |> load_groups()}
  end

  defp seasons_with_data do
    case Kits.list_seasons() do
      [] -> [Kits.current_season()]
      seasons -> seasons
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, form: to_form(Kits.change_team(%Team{})), team: %Team{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    team = Kits.get_team!(id)
    assign(socket, form: to_form(Kits.change_team(team)), team: team)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, team: nil)

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> load_groups()}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, socket |> assign(:search, "") |> load_groups()}
  end

  def handle_event("toggle_league", %{"id" => id}, socket) do
    id = String.to_integer(id)
    filter = socket.assigns.league_filter

    filter =
      if MapSet.member?(filter, id), do: MapSet.delete(filter, id), else: MapSet.put(filter, id)

    {:noreply, socket |> assign(:league_filter, filter) |> load_groups()}
  end

  def handle_event("all_leagues", _params, socket) do
    {:noreply, socket |> assign(:league_filter, MapSet.new()) |> load_groups()}
  end

  def handle_event("select_season", %{"season" => season}, socket) do
    # Die Liga haengt an der Saison – ein Wechsel ordnet die Gruppen neu, und
    # ein Ligenfilter aus der alten Saison zeigt auf Ligen, die hier andere
    # sind.
    {:noreply, socket |> assign(season: season, league_filter: MapSet.new()) |> load_groups()}
  end

  def handle_event("validate", %{"team" => attrs}, socket) do
    changeset = Kits.change_team(socket.assigns.team, attrs)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"team" => attrs}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Kits.create_team(attrs)
        :edit -> Kits.update_team(socket.assigns.team, attrs)
      end

    case result do
      {:ok, _team} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gespeichert.")
         |> load_groups()
         |> push_patch(to: ~p"/admin/vereine")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kits.get_team!() |> Kits.delete_team()

    {:noreply, socket |> put_flash(:info, "Verein gelöscht.") |> load_groups()}
  end

  # Alle Vereine der Saison, nach Liga gruppiert, danach durch Ligenfilter und
  # Suche. Gefiltert wird im Speicher: es sind ein paar Dutzend Vereine, und so
  # gilt dieselbe Umlaut-Nachsicht wie auf der Startseite.
  defp load_groups(socket) do
    %{search: search, league_filter: filter} = socket.assigns

    gruppen =
      socket.assigns.season
      |> Kits.list_teams_by_competition()
      |> Enum.filter(fn {competition, _teams} -> liga_gewaehlt?(competition, filter) end)
      |> Enum.map(fn {competition, teams} ->
        {competition, Enum.filter(teams, &trifft?(&1, competition, search))}
      end)
      |> Enum.reject(fn {_competition, teams} -> teams == [] end)

    assign(socket,
      groups: gruppen,
      leagues: Kits.list_competitions_for_season(socket.assigns.season),
      team_count: Enum.sum(Enum.map(gruppen, fn {_c, teams} -> length(teams) end))
    )
  end

  # Ein leerer Filter heisst "alle" – wie bei den Trikots. Die Gruppe „ohne
  # Liga" faellt weg, sobald jemand eine bestimmte Liga waehlt: sie ist keine.
  defp liga_gewaehlt?(competition, filter) do
    cond do
      MapSet.size(filter) == 0 -> true
      is_nil(competition) -> false
      true -> MapSet.member?(filter, competition.id)
    end
  end

  defp trifft?(team, competition, search) do
    Search.matches?([team.name, team.short_code, competition && competition.name], search)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Vereine"
        subtitle="Name, Kürzel und Vereinsfarbe. In welcher Liga der Verein spielt, steht unter Saison."
        current_path="/admin/vereine"
        new_path={~p"/admin/vereine/neu"}
        new_label="Verein anlegen"
      >
        <.admin_toolbar
          season={@season}
          seasons={@seasons}
          leagues={@leagues}
          league_filter={@league_filter}
          search={@search}
          search_placeholder="Verein, Kürzel oder Liga …"
          count_label={"#{@team_count} Vereine"}
        />

        <div
          :if={@groups == []}
          class="rounded-lg border border-dashed border-line px-6 py-12 text-center text-sm text-soft"
        >
          {if @search == "" and MapSet.size(@league_filter) == 0,
            do: "Noch kein Verein angelegt.",
            else: "Kein Verein in dieser Auswahl."}
        </div>

        <%!-- Eine Tabelle je Liga statt einer langen: 68 Vereine am Stueck sind
              eine Liste, in der man nichts wiederfindet. Die Ueberschrift sagt
              obendrein, worauf sich die Zuordnung bezieht – sie gilt nur fuer
              die gewaehlte Saison. --%>
        <section :for={{competition, teams} <- @groups} class="mb-8 last:mb-0">
          <div class="mb-2 flex flex-wrap items-baseline gap-3">
            <h2 class="kr-display text-lg leading-none">
              {if competition, do: competition.name, else: "Ohne Liga"}
            </h2>
            <span :if={competition} class="kr-eyebrow">
              {competition.country} · Liga {competition.tier}
            </span>
            <%!-- Diese Vereine tauchen in der Uebersicht nicht auf. Das soll
                  auffallen, nicht verschwinden. --%>
            <span :if={!competition} class="font-mono text-xs text-red-600">
              in {@season} keiner Liga zugeordnet
            </span>
            <span class="ml-auto font-mono text-xs text-soft">{length(teams)}</span>
          </div>

          <.admin_table rows={teams} empty_text="Kein Verein.">
            <:col :let={team} label="Farbe" class="w-14">
              <span
                class="block h-6 w-6 rounded-full ring-1 ring-black/10"
                style={"background-color: #{Color.team_color(team)}"}
                title={Color.team_color(team)}
              />
            </:col>
            <:col :let={team} label="Kürzel" class="font-mono text-xs font-semibold">
              {team.short_code}
            </:col>
            <:col :let={team} label="Name">{team.name}</:col>
            <:col :let={team} label="Shop" class="text-soft">
              <span :if={team.shop_url} class="font-mono text-xs">{host(team.shop_url)}</span>
              <span :if={!team.shop_url} class="text-xs">—</span>
            </:col>
            <:actions :let={team}>
              <.edit_link navigate={~p"/admin/vereine/#{team.id}"} />
              <.delete_button
                id={team.id}
                confirm={"#{team.name} löschen? Die Trikots des Vereins verschwinden mit."}
              />
            </:actions>
          </.admin_table>
        </section>
      </.admin_shell>

      <.form_modal
        :if={@live_action in [:new, :edit]}
        title={if @live_action == :new, do: "Verein anlegen", else: "Verein bearbeiten"}
        close_path={~p"/admin/vereine"}
      >
        <.form for={@form} id="team-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:name]} label="Name" placeholder="FC Bayern München" />
            <.input field={@form[:short_code]} label="Kürzel" placeholder="FCB" />
            <.input field={@form[:primary_color]} label="Vereinsfarbe" placeholder="#DC052D" />
            <p class="text-xs text-soft">
              Als Hex-Wert. Trikots ohne Bild werden in dieser Farbe gezeichnet.
            </p>
            <.input field={@form[:shop_url]} label="Shop" placeholder="https://…" />
          </div>
          <.form_actions close_path={~p"/admin/vereine"} />
        </.form>
      </.form_modal>
    </Layouts.app>
    """
  end

  defp host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> String.replace_prefix(host, "www.", "")
      _ -> url
    end
  end
end
