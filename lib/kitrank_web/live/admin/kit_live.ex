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
  alias Kitrank.Kits.ProductImages

  # Der Abruf haengt am Netz und an fremden Shops. Damit Tests den ganzen Weg
  # gehen koennen – Link eingeben, Bilder anklicken, speichern – ist er
  # austauschbar.
  @images Application.compile_env(:kitrank, :product_images, ProductImages)
  alias KitrankWeb.Color

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()

    {:ok,
     socket
     |> assign(
       page_title: "Trikots",
       season: season,
       candidates: [],
       fetching?: false,
       fetch_error: nil,
       league_filter: MapSet.new(),
       search: ""
     )
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

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, kit: nil, candidates: [], fetch_error: nil)
  end

  ## Bilder aus dem Shop holen

  @impl true
  def handle_event("fetch_images", %{"product_url" => url}, socket) do
    # In einem eigenen Prozess: ein Shop, der nicht antwortet, wuerde die
    # Oberflaeche sonst bis zum Timeout einfrieren – und ein eingefrorenes
    # Fenster sieht aus wie ein Fehler, obwohl nur gewartet wird.
    {:noreply,
     socket
     |> assign(fetching?: true, fetch_error: nil, candidates: [])
     |> start_async(:fetch_images, fn -> @images.fetch(url) end)}
  end

  @doc """
  Bild anklicken: der erste Klick macht es zum Freisteller, jeder weitere hängt
  ein Model-Bild an. Nochmal klicken nimmt es wieder raus.

  Bewusst keine Automatik: welches Bild der Freisteller ist, sieht man in zwei
  Sekunden und kein Skript zuverlässig.
  """
  def handle_event("toggle_image", %{"url" => url}, socket) do
    gewaehlt = picked(socket)

    gewaehlt =
      if url in gewaehlt, do: List.delete(gewaehlt, url), else: gewaehlt ++ [url]

    {:noreply, apply_picked(socket, gewaehlt)}
  end

  def handle_event("clear_images", _params, socket) do
    {:noreply, apply_picked(socket, [])}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> load_rows()}
  end

  def handle_event("toggle_league", %{"id" => id}, socket) do
    id = String.to_integer(id)
    filter = socket.assigns.league_filter

    filter =
      if MapSet.member?(filter, id), do: MapSet.delete(filter, id), else: MapSet.put(filter, id)

    {:noreply, socket |> assign(:league_filter, filter) |> load_rows()}
  end

  def handle_event("all_leagues", _params, socket) do
    {:noreply, socket |> assign(:league_filter, MapSet.new()) |> load_rows()}
  end

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
         |> push_patch(to: ~p"/admin/trikots")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, socket.assigns.kit, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kits.get_kit!() |> Kits.delete_kit()

    {:noreply, socket |> put_flash(:info, "Trikot gelöscht.") |> load_rows()}
  end

  @impl true
  def handle_async(:fetch_images, {:ok, ergebnis_oder_fehler}, socket) do
    case ergebnis_oder_fehler do
      {:ok, ergebnis} ->
        # Den Produktlink gleich als Shop-Deep-Link uebernehmen – dafuer ist er da.
        attrs = Map.put(current_attrs(socket), "source_shop_url", ergebnis.source_url)

        {:noreply,
         socket
         |> assign(fetching?: false, candidates: ergebnis.images)
         |> assign_form(socket.assigns.kit, Kits.change_kit(socket.assigns.kit, attrs))}

      {:error, grund} ->
        {:noreply, assign(socket, fetching?: false, fetch_error: ProductImages.message(grund))}
    end
  end

  # Der Abrufprozess selbst ist gestorben – auch das darf die Seite nicht
  # mitnehmen.
  def handle_async(:fetch_images, {:exit, grund}, socket) do
    require Logger
    Logger.warning("Bildabruf abgebrochen: #{inspect(grund)}")

    {:noreply,
     assign(socket,
       fetching?: false,
       fetch_error: "Der Abruf ist abgebrochen. Bild-Adressen kannst du von Hand einfügen."
     )}
  end

  # Die aktuell gewaehlten Bilder in Klick-Reihenfolge: Freisteller zuerst.
  defp picked(socket), do: picked_urls(socket.assigns.preview)

  defp picked_urls(preview) do
    Enum.reject([preview.cutout_url | preview.model_image_urls || []], &is_nil/1)
  end

  defp apply_picked(socket, urls) do
    attrs =
      socket
      |> current_attrs()
      |> Map.put("cutout_url", List.first(urls))
      |> Map.put("model_image_urls", Enum.drop(urls, 1))

    assign_form(socket, socket.assigns.kit, Kits.change_kit(socket.assigns.kit, attrs))
  end

  defp current_attrs(socket) do
    p = socket.assigns.preview

    %{
      "team_id" => p.team_id,
      "season" => p.season,
      "kit_type" => p.kit_type,
      "cutout_url" => p.cutout_url,
      "model_image_urls" => p.model_image_urls || [],
      "source_shop_url" => p.source_shop_url
    }
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
      rows:
        Kits.list_kits_for_admin(socket.assigns.season,
          competition_ids: MapSet.to_list(socket.assigns.league_filter),
          query: socket.assigns.search
        ),
      competitions: Kits.list_competitions(),
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

        <div :if={@competitions != []} class="mb-5 flex flex-wrap items-center gap-2">
          <span class="kr-eyebrow">Liga</span>
          <button
            type="button"
            phx-click="all_leagues"
            aria-pressed={to_string(MapSet.size(@league_filter) == 0)}
            class={[
              "rounded-full border px-3 py-1 text-xs transition",
              MapSet.size(@league_filter) == 0 && "border-transparent bg-ink text-chalk",
              MapSet.size(@league_filter) > 0 &&
                "border-line text-soft hover:border-ink hover:text-ink"
            ]}
          >
            Alle
          </button>
          <button
            :for={competition <- @competitions}
            type="button"
            phx-click="toggle_league"
            phx-value-id={competition.id}
            aria-pressed={to_string(MapSet.member?(@league_filter, competition.id))}
            class={[
              "rounded-full border px-3 py-1 text-xs transition",
              MapSet.member?(@league_filter, competition.id) && "border-transparent bg-ink text-chalk",
              !MapSet.member?(@league_filter, competition.id) &&
                "border-line text-soft hover:border-ink hover:text-ink"
            ]}
          >
            {competition.name}
          </button>
          <form phx-change="search" class="ml-auto flex items-center gap-2">
            <label for="q" class="sr-only">Nach Verein suchen</label>
            <input
              type="search"
              id="q"
              name="q"
              value={@search}
              phx-debounce="250"
              placeholder="Verein suchen …"
              class="w-48 rounded-md border border-line bg-panel px-3 py-1.5 text-xs"
            />
            <span class="shrink-0 whitespace-nowrap font-mono text-xs text-soft">
              {length(@rows)} Trikots
            </span>
          </form>
        </div>

        <.admin_table rows={@rows} empty_text={"Für #{@season} ist kein Trikot in dieser Auswahl."}>
          <:col :let={%{kit: kit}} label="" class="w-16">
            <span
              class="flex h-12 w-12 items-center justify-center rounded-md"
              style={"background-color: color-mix(in oklab, #{Color.team_color(kit.team)} 15%, #FFFFFF)"}
            >
              <.kit_figure kit={kit} team={kit.team} class="h-9 w-9" size={:thumb} />
            </span>
          </:col>
          <:col :let={%{kit: kit}} label="Verein">{kit.team.name}</:col>
          <:col :let={%{competition: competition}} label="Liga" class="text-soft">
            <span :if={competition} class="text-xs">{competition.name}</span>
            <%!-- Ohne Zuordnung taucht das Trikot in der Uebersicht nicht auf –
                  das soll hier auffallen, nicht verschwinden. --%>
            <span :if={!competition} class="font-mono text-xs text-red-600">keine Liga</span>
          </:col>
          <:col :let={%{kit: kit}} label="Typ">
            <span class="inline-flex items-center gap-2">
              <.kit_badge kit_type={kit.kit_type} class="bg-sunk text-soft" />
              {Kit.label(kit.kit_type)}
            </span>
          </:col>
          <:col :let={%{kit: kit}} label="Bilder" class="text-soft">
            <span class="font-mono text-xs">
              {if kit.cutout_url, do: "Cutout", else: "—"}
              {if kit.model_image_urls != [], do: "+#{length(kit.model_image_urls)}"}
            </span>
          </:col>
          <:col :let={%{kit: kit}} label="Shop" class="text-soft">
            <span class="font-mono text-xs">{if kit.source_shop_url, do: "ja", else: "—"}</span>
          </:col>
          <:actions :let={%{kit: kit}}>
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

        <.image_picker
          candidates={@candidates}
          picked={picked_urls(@preview)}
          fetching?={@fetching?}
          error={@fetch_error}
        />

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

  attr :candidates, :list, required: true
  attr :picked, :list, required: true
  attr :fetching?, :boolean, required: true
  attr :error, :string, default: nil

  # Produktlink rein, Bilder raus, anklicken. Die Reihenfolge der Klicks
  # bestimmt die Rollen: erstes Bild ist der Freisteller, die naechsten sind
  # Model-Bilder.
  defp image_picker(assigns) do
    ~H"""
    <div class="mb-6 rounded-lg border border-line bg-sunk p-4">
      <h3 class="kr-eyebrow">Bilder aus dem Shop holen</h3>
      <p class="mt-1 text-xs text-soft">
        Produktlink einfügen — danach anklicken, welche Bilder du willst.
      </p>

      <%!-- Ein eigenes Formular: nur so wird der Feldwert mitgeschickt, und
            Enter loest hier den Abruf aus statt das Trikot zu speichern.
            Deshalb steht der Picker auch ausserhalb des Trikot-Formulars –
            verschachtelte Formulare sind ungueltig. --%>
      <form id="image-picker-form" phx-submit="fetch_images" class="mt-3 flex gap-2">
        <label for="product_url" class="sr-only">Produktlink</label>
        <input
          type="url"
          id="product_url"
          name="product_url"
          required
          placeholder="https://shop.hsv.de/…/products/14284"
          class="min-w-0 flex-1 rounded-md border border-line bg-panel px-3 py-2 font-mono text-xs"
        />
        <button
          type="submit"
          phx-disable-with="Holt …"
          disabled={@fetching?}
          class="shrink-0 rounded-md border border-ink px-3 py-2 text-xs font-semibold transition hover:bg-panel disabled:opacity-40"
        >
          {if @fetching?, do: "Holt …", else: "Bilder holen"}
        </button>
      </form>

      <p :if={@error} class="mt-2 text-xs text-red-600">{@error}</p>

      <div :if={@candidates != []} class="mt-4">
        <div class="flex items-baseline gap-2">
          <p class="text-xs text-soft">
            {length(@candidates)} Bilder gefunden, {length(@picked)} gewählt
          </p>
          <button
            :if={@picked != []}
            type="button"
            phx-click="clear_images"
            class="ml-auto text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
          >
            Auswahl leeren
          </button>
        </div>

        <ul class="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-5">
          <li :for={url <- @candidates}>
            <button
              type="button"
              phx-click="toggle_image"
              phx-value-url={url}
              aria-pressed={to_string(url in @picked)}
              class={[
                "relative block aspect-square w-full overflow-hidden rounded-md border bg-white transition",
                url in @picked && "border-ink ring-2 ring-ink",
                url not in @picked && "border-line hover:border-ink/40"
              ]}
            >
              <img src={url} alt="" loading="lazy" class="h-full w-full object-contain p-1" />
              <span
                :if={url in @picked}
                class="absolute left-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-ink font-mono text-[10px] font-semibold text-chalk"
              >
                {Enum.find_index(@picked, &(&1 == url)) + 1}
              </span>
            </button>
            <p
              :if={url in @picked}
              class="mt-1 text-center font-mono text-[10px] text-soft"
            >
              {if Enum.find_index(@picked, &(&1 == url)) == 0, do: "Freisteller", else: "Model"}
            </p>
          </li>
        </ul>

        <p class="mt-3 text-xs text-soft">
          Der erste Klick macht das Bild zum Freisteller, jeder weitere hängt ein Model-Bild an.
        </p>
      </div>
    </div>
    """
  end
end
