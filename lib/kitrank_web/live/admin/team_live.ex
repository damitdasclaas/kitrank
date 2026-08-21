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

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Vereine", teams: Kits.list_teams())}
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
         |> assign(teams: Kits.list_teams())
         |> push_navigate(to: ~p"/admin/vereine")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kits.get_team!() |> Kits.delete_team()

    {:noreply, socket |> put_flash(:info, "Verein gelöscht.") |> assign(teams: Kits.list_teams())}
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
        <.admin_table rows={@teams} empty_text="Noch kein Verein angelegt.">
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
