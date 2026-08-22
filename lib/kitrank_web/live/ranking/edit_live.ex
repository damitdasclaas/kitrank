defmodule KitrankWeb.Ranking.EditLive do
  @moduledoc """
  Rangliste bearbeiten – wer den `edit_token` hat, darf das.

  Zwei Schritte statt einer langen Liste: erst auswählen, dann sortieren. Bei
  zwei vollen Ligen stehen über hundert Trikots zur Wahl, und die per Drag in
  eine Reihenfolge zu bringen wäre unbenutzbar. Ausgewählt wird deshalb in
  einem Raster, sortiert nur noch das, was übrig bleibt.

  Gespeichert wird laufend; einen Speichern-Knopf gibt es nicht.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.KitComponents
  import KitrankWeb.Ranking.Components

  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias Kitrank.Rankings
  alias KitrankWeb.Color

  @impl true
  def mount(%{"edit_token" => token}, _session, socket) do
    case Rankings.get_ranking_by_edit_token(token) do
      nil ->
        raise KitrankWeb.NotFoundError, "Rangliste nicht gefunden"

      ranking ->
        season = Kits.current_season()

        {:ok,
         socket
         |> assign(
           ranking: ranking,
           season: season,
           all_seasons: seasons_with_data(season),
           all_competitions: Kits.list_competitions(),
           all_teams: Kits.list_rankable_teams(),
           name_form: to_form(Rankings.change_ranking(ranking)),
           share_url: url(~p"/r/#{ranking.share_slug}"),
           detail: nil,
           # Aendert sich nur, wenn eine Notiz von ausserhalb ihres eigenen
           # Feldes gespeichert wird – siehe Kommentar an `entry_row/1`.
           note_epoch: 0
         )
         |> load_entries()
         |> init_scope()}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    title =
      case socket.assigns.live_action do
        :select -> "Trikots auswählen"
        _ -> "Rangliste sortieren"
      end

    {:noreply, assign(socket, page_title: title)}
  end

  # Der Ausschnitt steht im Socket, nicht in der Datenbank: er sagt nur, worüber
  # gerade entschieden wird, und gehört nicht zur Rangliste selbst. Beim
  # Wiederkommen ergibt er sich aus dem, was schon drin ist – wer bisher nur
  # HSV-Trikots gewählt hat, landet wieder dort.
  #
  # Eine leere Menge heißt überall "keine Einschränkung", wie beim Reveal-Raum.
  defp init_scope(socket) do
    eintraege = socket.assigns.entries

    scope =
      if eintraege == [] do
        %{
          seasons: MapSet.new([socket.assigns.season]),
          competitions: MapSet.new(),
          teams: MapSet.new()
        }
      else
        %{
          seasons: MapSet.new(eintraege, & &1.kit.season),
          competitions: MapSet.new(),
          teams: MapSet.new()
        }
      end

    socket |> assign(:scope, scope) |> load_catalog()
  end

  # Alle Saisons, für die es Daten gibt – plus die laufende, damit sie auch
  # vor dem ersten Trikot wählbar ist.
  defp seasons_with_data(current) do
    [current | Kits.list_seasons()] |> Enum.uniq() |> Enum.sort(:desc)
  end

  defp load_catalog(socket) do
    scope = socket.assigns.scope

    catalog =
      Kits.list_kits_for_scope(%{
        seasons: MapSet.to_list(scope.seasons),
        competition_ids: MapSet.to_list(scope.competitions),
        team_ids: MapSet.to_list(scope.teams)
      })

    # Bei mehreren Saisons nach Saison gruppieren, sonst nach Liga. Wer die
    # Trikots eines Vereins über Jahre sortiert, denkt in Jahren – wer eine
    # Saison rankt, in Ligen.
    mehrere_saisons? = MapSet.size(scope.seasons) != 1

    gruppen =
      if mehrere_saisons? do
        catalog
        |> Enum.group_by(& &1.kit.season)
        |> Enum.sort_by(&elem(&1, 0), :desc)
      else
        catalog
        |> Enum.group_by(& &1.competition.name)
        |> Enum.sort_by(fn {_name, [%{competition: c} | _]} -> {c.tier, c.name} end)
      end

    assign(socket, catalog: catalog, groups: gruppen, multi_season?: mehrere_saisons?)
  end

  ## Ausschnitt wählen

  @impl true
  def handle_event("toggle_filter", %{"axis" => axis, "value" => value}, socket) do
    achse = achse(axis)
    wert = if achse == :seasons, do: value, else: String.to_integer(value)

    scope =
      Map.update!(socket.assigns.scope, achse, fn menge ->
        if MapSet.member?(menge, wert),
          do: MapSet.delete(menge, wert),
          else: MapSet.put(menge, wert)
      end)

    {:noreply, socket |> assign(:scope, scope) |> load_catalog()}
  end

  def handle_event("clear_filter", %{"axis" => axis}, socket) do
    scope = Map.put(socket.assigns.scope, achse(axis), MapSet.new())
    {:noreply, socket |> assign(:scope, scope) |> load_catalog()}
  end

  ## Schnellauswahl – wirkt nur auf den gewählten Ausschnitt

  def handle_event("quick_select", %{"type" => type}, socket) do
    kit_ids = scoped_kit_ids(socket, type)
    ranking = socket.assigns.ranking

    if kit_ids != [] and Enum.all?(kit_ids, &MapSet.member?(socket.assigns.selected, &1)) do
      Enum.each(kit_ids, &Rankings.remove_kit(ranking, &1))
    else
      Rankings.add_kits(ranking, kit_ids)
    end

    {:noreply, load_entries(socket)}
  end

  def handle_event("toggle_group", %{"name" => name}, socket) do
    kit_ids = group_kit_ids(socket, name)
    ranking = socket.assigns.ranking

    if kit_ids != [] and Enum.all?(kit_ids, &MapSet.member?(socket.assigns.selected, &1)) do
      Enum.each(kit_ids, &Rankings.remove_kit(ranking, &1))
    else
      Rankings.add_kits(ranking, kit_ids)
    end

    {:noreply, load_entries(socket)}
  end

  def handle_event("toggle_kit", %{"id" => id}, socket) do
    id = String.to_integer(id)
    ranking = socket.assigns.ranking

    if MapSet.member?(socket.assigns.selected, id) do
      {:ok, _} = Rankings.remove_kit(ranking, id)
    else
      {:ok, _} = Rankings.add_kit(ranking, id)
    end

    {:noreply, load_entries(socket)}
  end

  ## Sortieren

  def handle_event("reorder", %{"kit_ids" => kit_ids}, socket) do
    ids = Enum.map(kit_ids, &String.to_integer/1)

    case Rankings.reorder(socket.assigns.ranking, ids) do
      :ok ->
        {:noreply, load_entries(socket)}

      {:error, :kit_ids_mismatch} ->
        # Kann passieren, wenn in einem zweiten Tab etwas geändert wurde. Dann
        # gilt der Serverstand, nicht das, was dieser Browser noch angezeigt hat.
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Die Liste hat sich zwischendurch geändert. Hier ist der aktuelle Stand."
         )
         |> load_entries()}
    end
  end

  def handle_event("move", %{"id" => id, "delta" => delta}, socket) do
    Rankings.move_entry(
      socket.assigns.ranking,
      String.to_integer(id),
      String.to_integer(delta)
    )

    {:noreply, load_entries(socket)}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    {:ok, _} = Rankings.remove_kit(socket.assigns.ranking, String.to_integer(id))
    {:noreply, load_entries(socket)}
  end

  def handle_event("save_note", %{"entry_id" => entry_id, "note" => note}, socket) do
    entry_id = String.to_integer(entry_id)

    case Enum.find(socket.assigns.entries, &(&1.id == entry_id)) do
      nil -> {:noreply, socket}
      entry -> {:noreply, note_saved(socket, entry, note)}
    end
  end

  ## Detailansicht beim Sortieren

  def handle_event("open_detail", %{"id" => id}, socket) do
    {:noreply, assign(socket, :detail, %{kit_id: String.to_integer(id), image: 0})}
  end

  def handle_event("close_detail", _params, socket), do: {:noreply, assign(socket, :detail, nil)}

  def handle_event("detail_image", %{"index" => index}, socket) do
    {:noreply,
     assign(socket, :detail, %{socket.assigns.detail | image: String.to_integer(index)})}
  end

  def handle_event("save_detail_note", %{"entry_id" => entry_id, "note" => note}, socket) do
    entry_id = String.to_integer(entry_id)

    case Enum.find(socket.assigns.entries, &(&1.id == entry_id)) do
      nil ->
        {:noreply, socket}

      entry ->
        # Die Notiz aus der Detailansicht muss auch in der Zeile darunter
        # ankommen. Deren Feld steht unter phx-update="ignore", damit der Cursor
        # beim Tippen nicht springt – ein neuer Epoch-Wert zwingt es dazu, sich
        # doch einmal neu aufzubauen.
        {:noreply,
         socket
         |> note_saved(entry, note)
         |> update(:note_epoch, &(&1 + 1))}
    end
  end

  ## Name

  def handle_event("save_name", %{"ranking" => attrs}, socket) do
    case Rankings.update_ranking(socket.assigns.ranking, attrs) do
      {:ok, ranking} ->
        {:noreply,
         assign(socket, ranking: ranking, name_form: to_form(Rankings.change_ranking(ranking)))}

      {:error, changeset} ->
        {:noreply, assign(socket, name_form: to_form(changeset))}
    end
  end

  defp note_saved(socket, entry, note) do
    case Rankings.update_note(entry, note) do
      {:ok, _} ->
        load_entries(socket)

      {:error, _changeset} ->
        put_flash(socket, :error, "Die Notiz ist zu lang – höchstens 500 Zeichen.")
    end
  end

  defp load_entries(socket) do
    entries = Rankings.list_entries(socket.assigns.ranking)

    assign(socket,
      entries: entries,
      selected: MapSet.new(entries, & &1.kit_id),
      count: length(entries)
    )
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-[1200px] px-4 pb-32 pt-8 sm:px-6 lg:px-8">
        <.ranking_header
          ranking={@ranking}
          name_form={@name_form}
          share_url={@share_url}
          season={@season}
          count={@count}
        />

        <.step_nav
          live_action={@live_action}
          edit_token={@ranking.edit_token}
          count={@count}
        />

        <.selection
          :if={@live_action == :select}
          groups={@groups}
          catalog={@catalog}
          selected={@selected}
          scope={@scope}
          all_seasons={@all_seasons}
          all_competitions={@all_competitions}
          all_teams={@all_teams}
          multi_season?={@multi_season?}
        />

        <.sorting
          :if={@live_action == :sort}
          entries={@entries}
          edit_token={@ranking.edit_token}
          note_epoch={@note_epoch}
        />
      </div>

      <.step_bar live_action={@live_action} edit_token={@ranking.edit_token} count={@count} />

      <.entry_detail
        :if={@detail && detail_entry(@entries, @detail)}
        entry={detail_entry(@entries, @detail)}
        index={detail_index(@entries, @detail)}
        total={@count}
        image={@detail.image}
      />
    </Layouts.app>
    """
  end

  defp detail_entry(entries, %{kit_id: kit_id}),
    do: Enum.find(entries, &(&1.kit_id == kit_id))

  defp detail_index(entries, %{kit_id: kit_id}),
    do: Enum.find_index(entries, &(&1.kit_id == kit_id))

  ## Auswahl-Ansicht

  attr :groups, :list, required: true
  attr :catalog, :list, required: true
  attr :selected, :any, required: true
  attr :scope, :map, required: true
  attr :all_seasons, :list, required: true
  attr :all_competitions, :list, required: true
  attr :all_teams, :list, required: true
  attr :multi_season?, :boolean, required: true

  defp selection(assigns) do
    ~H"""
    <div class="mt-8 space-y-4 rounded-lg border border-line p-5">
      <h2 class="kr-eyebrow">Worüber rankst du?</h2>

      <.filter_row axis="seasons" label="Saison" chosen={@scope.seasons}>
        <:chip :for={season <- @all_seasons} value={season} label={season} />
      </.filter_row>

      <.filter_row axis="competitions" label="Liga" chosen={@scope.competitions}>
        <:chip :for={c <- @all_competitions} value={c.id} label={c.name} />
      </.filter_row>

      <.filter_row axis="teams" label="Verein" chosen={@scope.teams}>
        <:chip :for={t <- @all_teams} value={t.id} label={t.short_code} title={t.name} />
      </.filter_row>

      <div :if={@catalog != []} class="border-t border-line pt-4">
        <div class="flex flex-wrap items-baseline gap-2">
          <h3 class="kr-eyebrow">Schnell auswählen</h3>
          <span class="text-[11px] text-soft">
            {length(@catalog)} Trikots · {scope_label(@scope, @all_teams)}
          </span>
        </div>
        <div class="mt-3 flex flex-wrap gap-2">
          <.quick_button
            :for={type <- available_types(@catalog)}
            type={type}
            label={Kit.label(type)}
            all_selected?={type_all_selected?(@catalog, @selected, type)}
          />
          <.quick_button
            type="all"
            label="Trikots"
            all_selected?={type_all_selected?(@catalog, @selected, "all")}
          />
        </div>
      </div>
    </div>

    <div
      :if={@catalog == []}
      class="mt-8 rounded-lg border border-dashed border-line p-12 text-center"
    >
      <p class="kr-display text-xl">Nichts im Ausschnitt</p>
      <p class="mx-auto mt-2 max-w-sm text-sm text-soft">
        Für diese Kombination gibt es keine Trikots. Nimm eine Einschränkung heraus.
      </p>
    </div>

    <section :for={{name, eintraege} <- @groups} class="mt-10">
      <div class="flex flex-wrap items-baseline gap-3 border-b border-line pb-2">
        <h2 class="kr-display text-lg">{name}</h2>
        <span class="kr-eyebrow">{length(eintraege)} Trikots</span>
        <button
          type="button"
          phx-click="toggle_group"
          phx-value-name={name}
          class="ml-auto rounded-md border border-line px-3 py-1 font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
        >
          {if group_all_selected?(eintraege, @selected), do: "Alle abwählen", else: "Alle auswählen"}
        </button>
      </div>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
        <.pick_tile
          :for={%{kit: kit} <- eintraege}
          kit={kit}
          team={kit.team}
          selected={MapSet.member?(@selected, kit.id)}
        />
      </div>
    </section>
    """
  end

  attr :axis, :string, required: true
  attr :label, :string, required: true
  attr :chosen, :any, required: true

  slot :chip do
    attr :value, :any, required: true
    attr :label, :string, required: true
    attr :title, :string
  end

  # Eine leere Menge heisst "keine Einschraenkung". Damit das nicht wie ein
  # Versehen aussieht, ist "Alle" ein eigener Knopf, der dann aktiv leuchtet.
  defp filter_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-baseline gap-2">
      <span class="kr-eyebrow w-14 shrink-0">{@label}</span>

      <button
        type="button"
        phx-click="clear_filter"
        phx-value-axis={@axis}
        aria-pressed={to_string(MapSet.size(@chosen) == 0)}
        class={[
          "rounded-full border px-3 py-1 text-xs transition",
          MapSet.size(@chosen) == 0 && "border-transparent bg-ink text-chalk",
          MapSet.size(@chosen) > 0 && "border-line text-soft hover:border-ink hover:text-ink"
        ]}
      >
        Alle
      </button>

      <button
        :for={chip <- @chip}
        type="button"
        phx-click="toggle_filter"
        phx-value-axis={@axis}
        phx-value-value={chip.value}
        title={Map.get(chip, :title)}
        aria-pressed={to_string(MapSet.member?(@chosen, chip.value))}
        class={[
          "rounded-full border px-3 py-1 text-xs transition",
          MapSet.member?(@chosen, chip.value) && "border-transparent bg-ink text-chalk",
          !MapSet.member?(@chosen, chip.value) &&
            "border-line text-soft hover:border-ink hover:text-ink"
        ]}
      >
        {chip.label}
      </button>
    </div>
    """
  end

  attr :kit, :map, required: true
  attr :team, :map, required: true
  attr :selected, :boolean, required: true

  defp pick_tile(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.team))

    ~H"""
    <button
      type="button"
      phx-click="toggle_kit"
      phx-value-id={@kit.id}
      aria-pressed={to_string(@selected)}
      class={[
        "group relative overflow-hidden rounded-lg border text-left transition",
        @selected && "border-transparent ring-2",
        !@selected && "border-line hover:border-ink/30"
      ]}
      style={@selected && "--tw-ring-color: #{@color}"}
    >
      <div
        class="relative flex aspect-square items-center justify-center p-4"
        style={"background-color: color-mix(in oklab, #{@color} 14%, #FFFFFF)"}
      >
        <.kit_figure kit={@kit} team={@team} class="h-full w-full" />
        <span
          :if={@selected}
          class="absolute right-1.5 top-1.5 flex h-5 w-5 items-center justify-center rounded-full"
          style={"background-color: #{@color}; color: #{Color.readable_on(@color)}"}
        >
          <.icon name="hero-check-mini" class="size-3" />
        </span>
      </div>
      <div class="flex items-center gap-1.5 border-t border-line px-2 py-1.5">
        <span class="font-mono text-[10px] font-semibold" style={"color: #{@color}"}>
          {@team.short_code}
        </span>
        <span class="truncate text-[11px] text-soft">{Kit.label(@kit.kit_type)}</span>
      </div>
    </button>
    """
  end

  ## Sortier-Ansicht

  attr :entries, :list, required: true
  attr :edit_token, :string, required: true
  attr :note_epoch, :integer, default: 0

  defp sorting(assigns) do
    ~H"""
    <div
      :if={@entries == []}
      class="mt-10 rounded-lg border border-dashed border-line p-12 text-center"
    >
      <p class="kr-display text-xl">Noch nichts ausgewählt</p>
      <p class="mx-auto mt-2 max-w-sm text-sm text-soft">
        Such dir erst ein paar Trikots aus, dann kannst du sie hier in eine Reihenfolge bringen.
      </p>
      <.link
        navigate={~p"/rankings/#{@edit_token}/auswahl"}
        class="mt-5 inline-block rounded-md bg-ink px-4 py-2 text-sm font-semibold text-chalk"
      >
        Trikots auswählen
      </.link>
    </div>

    <ul
      :if={@entries != []}
      id="ranking-entries"
      phx-hook="Sortable"
      class="mt-8 space-y-2"
    >
      <.entry_row
        :for={{entry, index} <- Enum.with_index(@entries)}
        entry={entry}
        index={index}
        last?={index == length(@entries) - 1}
        note_epoch={@note_epoch}
      />
    </ul>

    <p :if={@entries != []} class="mt-4 text-xs text-soft">
      Ziehen am Griff sortiert um. Ohne Maus gehen auch die Pfeile — beides speichert sofort.
    </p>
    """
  end

  ## Bausteine der Auswahl

  # "all" nimmt alles aus den vorgewaehlten Ligen, sonst nur den Kit-Typ.
  defp achse("seasons"), do: :seasons
  defp achse("competitions"), do: :competitions
  defp achse("teams"), do: :teams

  defp scoped_kit_ids(socket, "all"), do: Enum.map(socket.assigns.catalog, & &1.kit.id)

  defp scoped_kit_ids(socket, kit_type) do
    socket.assigns.catalog
    |> Enum.filter(&(&1.kit.kit_type == kit_type))
    |> Enum.map(& &1.kit.id)
  end

  defp group_kit_ids(socket, name) do
    case Enum.find(socket.assigns.groups, fn {gruppe, _} -> gruppe == name end) do
      nil -> []
      {_gruppe, eintraege} -> Enum.map(eintraege, & &1.kit.id)
    end
  end

  # Nur Kit-Typen anbieten, die es im Ausschnitt ueberhaupt gibt – ein Knopf
  # "Sonder", der nichts tut, waere nur Rauschen.
  defp available_types(catalog) do
    vorhanden = MapSet.new(catalog, & &1.kit.kit_type)
    Enum.filter(Kit.kit_types(), &MapSet.member?(vorhanden, &1))
  end

  defp type_all_selected?(catalog, selected, type) do
    ids =
      catalog
      |> Enum.filter(&(type == "all" or &1.kit.kit_type == type))
      |> Enum.map(& &1.kit.id)

    ids != [] and Enum.all?(ids, &MapSet.member?(selected, &1))
  end

  defp group_all_selected?(eintraege, selected) do
    eintraege != [] and Enum.all?(eintraege, &MapSet.member?(selected, &1.kit.id))
  end

  # Kurzform des Ausschnitts fuer die Zeile ueber der Schnellauswahl.
  defp scope_label(scope, all_teams) do
    teile = [
      saison_teil(scope.seasons),
      if(MapSet.size(scope.teams) > 0, do: team_teil(scope.teams, all_teams))
    ]

    teile |> Enum.reject(&is_nil/1) |> Enum.join(", ")
  end

  defp saison_teil(seasons) do
    case MapSet.size(seasons) do
      0 -> "alle Saisons"
      1 -> MapSet.to_list(seasons) |> hd()
      n -> "#{n} Saisons"
    end
  end

  defp team_teil(teams, all_teams) do
    namen =
      all_teams
      |> Enum.filter(&MapSet.member?(teams, &1.id))
      |> Enum.map(& &1.short_code)

    case namen do
      [einer] -> einer
      viele -> "#{length(viele)} Vereine"
    end
  end

  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :all_selected?, :boolean, required: true

  defp quick_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="quick_select"
      phx-value-type={@type}
      aria-pressed={to_string(@all_selected?)}
      class={[
        "flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-xs transition",
        @all_selected? && "border-ink bg-sunk font-medium text-ink",
        !@all_selected? && "border-line text-soft hover:border-ink hover:text-ink"
      ]}
    >
      <.icon
        name={if @all_selected?, do: "hero-minus-mini", else: "hero-plus-mini"}
        class="size-3"
      />
      {if @all_selected?, do: "#{@label} abwählen", else: "Alle #{@label}"}
    </button>
    """
  end

  ## Detailansicht beim Sortieren

  attr :entry, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :image, :integer, required: true

  defp entry_detail(assigns) do
    images = kit_images(assigns.entry.kit)

    assigns =
      assigns
      |> assign(:images, images)
      |> assign(:src, Enum.at(images, assigns.image))
      |> assign(:color, Color.team_color(assigns.entry.kit.team))

    ~H"""
    <.modal
      id="entry-detail"
      on_close="close_detail"
      label={"#{@entry.kit.team.name} – #{Kit.label(@entry.kit.kit_type)}"}
      size="max-w-4xl"
    >
      <%!-- Das Bild bekommt drei von fuenf Spalten: es ist der Grund, warum man
            das Detail ueberhaupt aufmacht. --%>
      <div class="grid gap-0 sm:grid-cols-5">
        <div class="sm:col-span-3">
          <div
            class="flex aspect-square items-center justify-center rounded-tl-xl p-4 sm:p-8"
            style={"background-color: color-mix(in oklab, #{@color} 13%, #FFFFFF)"}
          >
            <.kit_figure
              kit={@entry.kit}
              team={@entry.kit.team}
              image_url={@src}
              size={:full}
              class="h-full w-full"
            />
          </div>

          <div :if={length(@images) > 1} class="border-t border-line px-4 py-3">
            <.kit_thumbstrip
              kit={@entry.kit}
              team={@entry.kit.team}
              images={@images}
              index={@image}
              event="detail_image"
            />
            <p class="mt-2 text-[11px] text-soft">{image_role(@image)}</p>
          </div>
        </div>

        <div class="flex flex-col border-t border-line p-5 sm:col-span-2 sm:border-l sm:border-t-0">
          <p class="kr-eyebrow">Platz {@index + 1} von {@total}</p>
          <h2 class="kr-display mt-1.5 text-2xl leading-tight">{@entry.kit.team.name}</h2>
          <p class="mt-1 flex items-baseline gap-2">
            <span class="font-mono text-xs font-semibold" style={"color: #{@color}"}>
              {@entry.kit.team.short_code}
            </span>
            <span class="text-sm text-soft">{Kit.label(@entry.kit.kit_type)}</span>
          </p>

          <form
            id="detail-note"
            phx-change="save_detail_note"
            class="mt-5 flex min-h-0 flex-1 flex-col"
          >
            <label for="detail-note-field" class="kr-eyebrow">Notiz</label>
            <input type="hidden" name="entry_id" value={@entry.id} />
            <textarea
              id="detail-note-field"
              name="note"
              rows="7"
              maxlength="500"
              phx-debounce="600"
              placeholder="Warum steht es genau hier? Was stört, was gefällt?"
              class="mt-2 w-full flex-1 resize-y rounded-md border border-line bg-panel px-3 py-2.5 text-sm leading-relaxed placeholder:text-soft/70"
            >{@entry.note}</textarea>
            <p class="mt-1 text-xs text-soft">
              Höchstens 500 Zeichen. Wird laufend gespeichert und steht später im Reveal.
            </p>
          </form>

          <a
            :if={@entry.kit.source_shop_url}
            href={@entry.kit.source_shop_url}
            target="_blank"
            rel="noopener noreferrer"
            class="mt-4 inline-flex items-center gap-1 text-xs text-soft underline underline-offset-4 hover:text-ink"
          >
            Im Shop ansehen <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
          </a>

          <div class="mt-5 flex flex-wrap gap-2 border-t border-line pt-4">
            <button
              type="button"
              phx-click="move"
              phx-value-id={@entry.kit_id}
              phx-value-delta="-1"
              disabled={@index == 0}
              class="flex items-center gap-1 rounded-md border border-line px-3 py-1.5 text-xs transition enabled:hover:border-ink disabled:opacity-30"
            >
              <.icon name="hero-chevron-up-mini" class="size-3.5" /> Höher
            </button>
            <button
              type="button"
              phx-click="move"
              phx-value-id={@entry.kit_id}
              phx-value-delta="1"
              disabled={@index == @total - 1}
              class="flex items-center gap-1 rounded-md border border-line px-3 py-1.5 text-xs transition enabled:hover:border-ink disabled:opacity-30"
            >
              <.icon name="hero-chevron-down-mini" class="size-3.5" /> Tiefer
            </button>
            <button
              type="button"
              phx-click="remove"
              phx-value-id={@entry.kit_id}
              class="ml-auto rounded-md border border-line px-3 py-1.5 text-xs text-soft transition hover:border-red-500 hover:text-red-600"
            >
              Aus der Liste nehmen
            </button>
          </div>
        </div>
      </div>
    </.modal>
    """
  end
end
