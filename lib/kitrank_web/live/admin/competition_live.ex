defmodule KitrankWeb.Admin.CompetitionLive do
  @moduledoc """
  Ligen. `tier` steuert Sortierung und Gruppierung der Übersicht – bewusst ein
  eigenes Feld, damit eine ausländische Liga kein Sonderfall im Code wird.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components

  alias Kitrank.Kits
  alias Kitrank.Kits.Competition

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Ligen",
       competitions: Kits.list_competitions(),
       sport_options: sport_options()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    competition = %Competition{tier: 1, country: "DE"}
    assign(socket, form: to_form(Kits.change_competition(competition)), competition: competition)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    competition = Kits.get_competition!(id)
    assign(socket, form: to_form(Kits.change_competition(competition)), competition: competition)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, competition: nil)

  @impl true
  def handle_event("validate", %{"competition" => attrs}, socket) do
    changeset = Kits.change_competition(socket.assigns.competition, attrs)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"competition" => attrs}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Kits.create_competition(attrs)
        :edit -> Kits.update_competition(socket.assigns.competition, attrs)
      end

    case result do
      {:ok, _competition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gespeichert.")
         |> assign(competitions: Kits.list_competitions())
         |> push_navigate(to: ~p"/admin/ligen")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    competition = Kits.get_competition!(id)

    case Kits.delete_competition(competition) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gelöscht.")
         |> assign(competitions: Kits.list_competitions())}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Geht nicht — an dieser Liga hängen noch Saison-Zuordnungen."
         )}
    end
  end

  defp sport_options do
    Enum.map(Kits.list_sports(), &{&1.name, &1.id})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Ligen"
        subtitle="Die Übersicht gruppiert nach diesen Ligen und sortiert nach ihrer Stufe."
        current_path="/admin/ligen"
        new_path={~p"/admin/ligen/neu"}
        new_label="Liga anlegen"
      >
        <div
          :if={@sport_options == []}
          class="mb-4 rounded-lg border border-dashed border-line p-5 text-sm"
        >
          Erst braucht es eine <.link
            navigate={~p"/admin/sportarten"}
            class="underline underline-offset-4"
          >Sportart</.link>,
          dann lässt sich eine Liga anlegen.
        </div>

        <.admin_table rows={@competitions} empty_text="Noch keine Liga angelegt.">
          <:col :let={c} label="Name">{c.name}</:col>
          <:col :let={c} label="Sportart" class="text-soft">{c.sport.name}</:col>
          <:col :let={c} label="Land" class="font-mono text-xs">{c.country}</:col>
          <:col :let={c} label="Stufe" class="font-mono text-xs tabular-nums">{c.tier}</:col>
          <:actions :let={c}>
            <.edit_link navigate={~p"/admin/ligen/#{c.id}"} />
            <.delete_button id={c.id} confirm={"#{c.name} wirklich löschen?"} />
          </:actions>
        </.admin_table>
      </.admin_shell>

      <.form_modal
        :if={@live_action in [:new, :edit]}
        title={if @live_action == :new, do: "Liga anlegen", else: "Liga bearbeiten"}
        close_path={~p"/admin/ligen"}
      >
        <.form for={@form} id="competition-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:sport_id]} type="select" label="Sportart" options={@sport_options} />
            <.input field={@form[:name]} label="Name" placeholder="Bundesliga" />
            <.input field={@form[:country]} label="Land" placeholder="DE" />
            <.input
              field={@form[:tier]}
              type="number"
              label="Stufe"
              min="1"
            />
            <p class="text-xs text-soft">
              Die Stufe bestimmt die Reihenfolge in der Übersicht: 1 steht oben.
            </p>
          </div>
          <.form_actions close_path={~p"/admin/ligen"} />
        </.form>
      </.form_modal>
    </Layouts.app>
    """
  end
end
