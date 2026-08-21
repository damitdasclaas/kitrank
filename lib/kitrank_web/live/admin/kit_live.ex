defmodule KitrankWeb.Admin.KitLive do
  @moduledoc """
  Trikots: Kit-Typ, Cutout, Model-Bilder und der Shop-Deep-Link.

  Bilder werden hier nur verlinkt, nicht hochgeladen – KitRank hostet keine
  Trikotbilder (Architektur Abschnitt 5). Bleibt ein Feld leer, zeichnet die
  Übersicht das Trikot in den Vereinsfarben.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components
  import KitrankWeb.KitComponents, only: [kit_figure: 1, kit_badge: 1]

  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias KitrankWeb.Color

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()

    {:ok,
     socket
     |> assign(page_title: "Trikots", season: season)
     |> load_rows()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    kit = %Kit{season: socket.assigns.season, kit_type: "home", model_image_urls: []}
    assign_form(socket, kit, Kits.change_kit(kit))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    kit = Kits.get_kit!(id)
    assign_form(socket, kit, Kits.change_kit(kit))
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, kit: nil)

  @impl true
  def handle_event("select_season", %{"season" => season}, socket) do
    {:noreply, socket |> assign(season: season) |> load_rows()}
  end

  def handle_event("validate", %{"kit" => attrs}, socket) do
    attrs = normalize(attrs)
    changeset = Kits.change_kit(socket.assigns.kit, attrs)

    {:noreply, assign_form(socket, socket.assigns.kit, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"kit" => attrs}, socket) do
    attrs = normalize(attrs)

    result =
      case socket.assigns.live_action do
        :new -> Kits.create_kit(attrs)
        :edit -> Kits.update_kit(socket.assigns.kit, attrs)
      end

    case result do
      {:ok, kit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gespeichert.")
         |> assign(season: kit.season)
         |> load_rows()
         |> push_navigate(to: ~p"/admin/trikots")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, socket.assigns.kit, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kits.get_kit!() |> Kits.delete_kit()

    {:noreply, socket |> put_flash(:info, "Trikot gelöscht.") |> load_rows()}
  end

  # Model-Bilder kommen als Textfeld mit einer URL pro Zeile herein – das ist
  # deutlich weniger fummelig als dynamisch wachsende Einzelfelder und passt zu
  # dem, was man ohnehin aus dem Shop kopiert.
  defp normalize(attrs) do
    Map.update(attrs, "model_image_urls", [], fn
      value when is_binary(value) -> String.split(value, ~r/\s*\n\s*/, trim: true)
      value when is_list(value) -> value
      _ -> []
    end)
  end

  # Der Vorschau-Kit spiegelt die aktuelle Eingabe, damit man sieht, was in der
  # Uebersicht ankommt, bevor man speichert.
  defp assign_form(socket, kit, changeset) do
    preview = Ecto.Changeset.apply_changes(changeset)
    team = preview.team_id && find_team(socket, preview.team_id)

    socket
    |> assign(kit: kit, form: to_form(changeset), preview: preview, preview_team: team)
    |> assign(:image_lines, Enum.join(preview.model_image_urls || [], "\n"))
  end

  defp find_team(socket, team_id) do
    Enum.find(socket.assigns.teams, &(&1.id == team_id))
  end

  defp load_rows(socket) do
    teams = Kits.list_teams()

    assign(socket,
      rows: Kits.list_kits(socket.assigns.season),
      seasons: Enum.uniq([socket.assigns.season, Kits.current_season()] ++ Kits.list_seasons()),
      teams: teams,
      team_options: Enum.map(teams, &{"#{&1.name} (#{&1.short_code})", &1.id}),
      type_options: Enum.map(Kit.kit_types(), &{Kit.label(&1), &1})
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Trikots"
        subtitle="Bilder werden verlinkt, nicht hochgeladen. Fehlt eins, zeichnet die Übersicht das Trikot."
        current_path="/admin/trikots"
        new_path={~p"/admin/trikots/neu"}
        new_label="Trikot anlegen"
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

        <.admin_table rows={@rows} empty_text={"Für #{@season} ist noch kein Trikot angelegt."}>
          <:col :let={kit} label="" class="w-16">
            <span
              class="flex h-12 w-12 items-center justify-center rounded-md"
              style={"background-color: color-mix(in oklab, #{Color.team_color(kit.team)} 15%, #FFFFFF)"}
            >
              <.kit_figure kit={kit} team={kit.team} class="h-9 w-9" />
            </span>
          </:col>
          <:col :let={kit} label="Verein">{kit.team.name}</:col>
          <:col :let={kit} label="Typ">
            <span class="inline-flex items-center gap-2">
              <.kit_badge kit_type={kit.kit_type} class="bg-sunk text-soft" />
              {Kit.label(kit.kit_type)}
            </span>
          </:col>
          <:col :let={kit} label="Bilder" class="text-soft">
            <span class="font-mono text-xs">
              {if kit.cutout_url, do: "Cutout", else: "—"}
              {if kit.model_image_urls != [], do: "+#{length(kit.model_image_urls)}"}
            </span>
          </:col>
          <:col :let={kit} label="Shop" class="text-soft">
            <span class="font-mono text-xs">{if kit.source_shop_url, do: "ja", else: "—"}</span>
          </:col>
          <:actions :let={kit}>
            <.edit_link navigate={~p"/admin/trikots/#{kit.id}"} />
            <.delete_button
              id={kit.id}
              confirm={"#{kit.team.name} #{Kit.label(kit.kit_type)} löschen?"}
            />
          </:actions>
        </.admin_table>
      </.admin_shell>

      <.form_modal
        :if={@live_action in [:new, :edit]}
        title={if @live_action == :new, do: "Trikot anlegen", else: "Trikot bearbeiten"}
        close_path={~p"/admin/trikots"}
      >
        <div
          :if={@team_options == []}
          class="mb-4 rounded-lg border border-dashed border-line p-4 text-sm"
        >
          Erst braucht es einen <.link
            navigate={~p"/admin/vereine"}
            class="underline underline-offset-4"
          >Verein</.link>.
        </div>

        <.form for={@form} id="kit-form" phx-change="validate" phx-submit="save">
          <div class="flex gap-5">
            <div
              :if={@preview_team}
              class="hidden h-28 w-24 shrink-0 items-center justify-center rounded-lg sm:flex"
              style={"background-color: color-mix(in oklab, #{Color.team_color(@preview_team)} 15%, #FFFFFF)"}
              aria-hidden="true"
            >
              <.kit_figure kit={@preview} team={@preview_team} class="h-20 w-20" />
            </div>

            <div class="min-w-0 flex-1 space-y-4">
              <.input field={@form[:team_id]} type="select" label="Verein" options={@team_options} />
              <.input field={@form[:kit_type]} type="select" label="Typ" options={@type_options} />
              <.input field={@form[:season]} label="Saison" placeholder="2026/27" />
            </div>
          </div>

          <div class="mt-4 space-y-4">
            <.input field={@form[:cutout_url]} label="Cutout-Bild" placeholder="https://…" />

            <div>
              <label for="kit_model_image_urls" class="text-sm font-medium">Model-Bilder</label>
              <textarea
                id="kit_model_image_urls"
                name="kit[model_image_urls]"
                rows="3"
                placeholder="https://…\nhttps://…"
                class="mt-1.5 w-full rounded-md border border-line bg-panel px-3 py-2 font-mono text-xs"
              >{@image_lines}</textarea>
              <p class="mt-1 text-xs text-soft">Eine URL pro Zeile.</p>
              <p
                :for={msg <- Enum.map(@form[:model_image_urls].errors, &translate_error/1)}
                class="mt-1 text-xs text-red-600"
              >
                {msg}
              </p>
            </div>

            <.input field={@form[:source_shop_url]} label="Shop-Link" placeholder="https://…" />
          </div>

          <.form_actions close_path={~p"/admin/trikots"} />
        </.form>
      </.form_modal>
    </Layouts.app>
    """
  end
end
