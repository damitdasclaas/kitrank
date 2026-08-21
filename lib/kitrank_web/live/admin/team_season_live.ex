defmodule KitrankWeb.Admin.TeamSeasonLive do
  @moduledoc """
  Wer spielt in welcher Saison in welcher Liga.

  Das ist die Stelle, an der Auf- und Abstieg gepflegt wird – einmal im Jahr.
  Die Vereins-Stammdaten bleiben dabei unangetastet, deshalb hängt die Liga hier
  und nicht am Verein.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components

  alias Kitrank.Kits
  alias Kitrank.Kits.TeamSeason

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()

    {:ok,
     socket
     |> assign(page_title: "Saison", season: season)
     |> load_rows()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    team_season = %TeamSeason{season: socket.assigns.season}
    assign(socket, form: to_form(Kits.change_team_season(team_season)), team_season: team_season)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    team_season = Kits.get_team_season!(id)
    assign(socket, form: to_form(Kits.change_team_season(team_season)), team_season: team_season)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, team_season: nil)

  @impl true
  def handle_event("select_season", %{"season" => season}, socket) do
    {:noreply, socket |> assign(season: season) |> load_rows()}
  end

  def handle_event("validate", %{"team_season" => attrs}, socket) do
    changeset = Kits.change_team_season(socket.assigns.team_season, attrs)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"team_season" => attrs}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Kits.create_team_season(attrs)
        :edit -> Kits.update_team_season(socket.assigns.team_season, attrs)
      end

    case result do
      {:ok, team_season} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gespeichert.")
         |> assign(season: team_season.season)
         |> load_rows()
         |> push_navigate(to: ~p"/admin/saison")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kits.get_team_season!() |> Kits.delete_team_season()

    {:noreply, socket |> put_flash(:info, "Zuordnung gelöscht.") |> load_rows()}
  end

  defp load_rows(socket) do
    assign(socket,
      rows: Kits.list_team_seasons(socket.assigns.season),
      seasons: known_seasons(socket.assigns.season),
      team_options: Enum.map(Kits.list_teams(), &{"#{&1.name} (#{&1.short_code})", &1.id}),
      competition_options:
        Enum.map(Kits.list_competitions(), &{"#{&1.name} · #{&1.country}", &1.id})
    )
  end

  # Vorhandene Saisons plus die laufende und die kommende – damit die naechste
  # Saison eingetragen werden kann, bevor es dort Daten gibt.
  defp known_seasons(current) do
    next = Kits.Season.from_start_year(next_start_year())

    [current, Kits.current_season(), next]
    |> Enum.concat(Kits.list_seasons())
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  defp next_start_year do
    {:ok, {start_year, _}} = Kits.Season.parse(Kits.current_season())
    start_year + 1
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Saison"
        subtitle="Auf- und Abstieg: hier bekommt jeder Verein seine Liga für eine Saison."
        current_path="/admin/saison"
        new_path={~p"/admin/saison/neu"}
        new_label="Zuordnung anlegen"
      >
        <div class="mb-5 flex items-center gap-2">
          <span class="kr-eyebrow">Saison</span>
          <div class="flex flex-wrap gap-1 rounded-lg border border-line bg-sunk p-1">
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

        <.admin_table
          rows={@rows}
          empty_text={"Für #{@season} ist noch kein Verein zugeordnet — die Übersicht bleibt dadurch leer."}
        >
          <:col :let={row} label="Verein">{row.team.name}</:col>
          <:col :let={row} label="Kürzel" class="font-mono text-xs">{row.team.short_code}</:col>
          <:col :let={row} label="Liga">{row.competition.name}</:col>
          <:col :let={row} label="Stufe" class="font-mono text-xs tabular-nums">
            {row.competition.tier}
          </:col>
          <:actions :let={row}>
            <.edit_link navigate={~p"/admin/saison/#{row.id}"} />
            <.delete_button
              id={row.id}
              label="Entfernen"
              confirm={"#{row.team.name} aus #{row.competition.name} #{row.season} entfernen?"}
            />
          </:actions>
        </.admin_table>
      </.admin_shell>

      <.form_modal
        :if={@live_action in [:new, :edit]}
        title={if @live_action == :new, do: "Zuordnung anlegen", else: "Zuordnung bearbeiten"}
        close_path={~p"/admin/saison"}
        hint="Ein Verein spielt pro Saison in genau einer Liga."
      >
        <.form for={@form} id="team_season-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:team_id]} type="select" label="Verein" options={@team_options} />
            <.input
              field={@form[:competition_id]}
              type="select"
              label="Liga"
              options={@competition_options}
            />
            <.input field={@form[:season]} label="Saison" placeholder="2026/27" />
          </div>
          <.form_actions close_path={~p"/admin/saison"} />
        </.form>
      </.form_modal>
    </Layouts.app>
    """
  end
end
