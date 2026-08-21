defmodule KitrankWeb.Admin.SportLive do
  @moduledoc """
  Sportarten. Heute steht hier eine Zeile – die Tabelle existiert, damit eine
  zweite Sportart später ein Datensatz ist und keine Migration.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components

  alias Kitrank.Kits
  alias Kitrank.Kits.Sport

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sportarten", sports: Kits.list_sports())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, form: to_form(Kits.change_sport(%Sport{})), sport: %Sport{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    sport = Kits.get_sport!(id)
    assign(socket, form: to_form(Kits.change_sport(sport)), sport: sport)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, sport: nil)

  @impl true
  def handle_event("validate", %{"sport" => attrs}, socket) do
    changeset = Kits.change_sport(socket.assigns.sport, attrs)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"sport" => attrs}, socket) do
    save(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    sport = Kits.get_sport!(id)

    case Kits.delete_sport(sport) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Gelöscht.") |> assign(sports: Kits.list_sports())}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Geht nicht — an dieser Sportart hängen noch Ligen.")}
    end
  end

  defp save(socket, :new, attrs) do
    case Kits.create_sport(attrs) do
      {:ok, _sport} -> {:noreply, saved(socket, "Sportart angelegt.")}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save(socket, :edit, attrs) do
    case Kits.update_sport(socket.assigns.sport, attrs) do
      {:ok, _sport} -> {:noreply, saved(socket, "Gespeichert.")}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp saved(socket, message) do
    socket
    |> put_flash(:info, message)
    |> assign(sports: Kits.list_sports())
    |> push_navigate(to: ~p"/admin/sportarten")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Sportarten"
        subtitle="Bleibt vorerst bei Fußball. Eine weitere Sportart ist hier eine neue Zeile."
        current_path="/admin/sportarten"
        new_path={~p"/admin/sportarten/neu"}
        new_label="Sportart anlegen"
      >
        <.admin_table rows={@sports} empty_text="Noch keine Sportart angelegt.">
          <:col :let={sport} label="Name">{sport.name}</:col>
          <:col :let={sport} label="Kürzel" class="font-mono text-xs">{sport.slug}</:col>
          <:actions :let={sport}>
            <.edit_link navigate={~p"/admin/sportarten/#{sport.id}"} />
            <.delete_button id={sport.id} confirm={"#{sport.name} wirklich löschen?"} />
          </:actions>
        </.admin_table>
      </.admin_shell>

      <.form_modal
        :if={@live_action in [:new, :edit]}
        title={if @live_action == :new, do: "Sportart anlegen", else: "Sportart bearbeiten"}
        close_path={~p"/admin/sportarten"}
      >
        <.form for={@form} id="sport-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:name]} label="Name" placeholder="Fußball" />
            <.input
              field={@form[:slug]}
              label="Kürzel"
              placeholder="football"
              phx-debounce="300"
            />
          </div>
          <.form_actions close_path={~p"/admin/sportarten"} />
        </.form>
      </.form_modal>
    </Layouts.app>
    """
  end
end
