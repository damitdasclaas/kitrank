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
           overview: Kits.overview(season),
           name_form: to_form(Rankings.change_ranking(ranking)),
           share_url: url(~p"/r/#{ranking.share_slug}"),
           detail: nil,
           # Aendert sich nur, wenn eine Notiz von ausserhalb ihres eigenen
           # Feldes gespeichert wird – siehe Kommentar an `entry_row/1`.
           note_epoch: 0
         )
         |> load_entries()
         |> init_leagues()}
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

  # Die Liga-Vorauswahl steht im Socket, nicht in der Datenbank: sie sagt nur,
  # worueber gerade entschieden wird, und gehoert nicht zur Rangliste selbst.
  # Beim Wiederkommen ergibt sie sich aus dem, was schon drin ist – wer bisher
  # nur Bundesliga gewaehlt hat, landet wieder dort.
  defp init_leagues(socket) do
    gewaehlt =
      for {competition, teams} <- socket.assigns.overview,
          {_team, kits} <- teams,
          kit <- kits,
          MapSet.member?(socket.assigns.selected, kit.id),
          into: MapSet.new(),
          do: competition.id

    active =
      if MapSet.size(gewaehlt) > 0,
        do: gewaehlt,
        else: MapSet.new(socket.assigns.overview, fn {competition, _} -> competition.id end)

    assign(socket, :active_leagues, active)
  end

  ## Ligen-Vorauswahl

  @impl true
  def handle_event("toggle_league", %{"id" => id}, socket) do
    id = String.to_integer(id)
    active = socket.assigns.active_leagues

    active =
      if MapSet.member?(active, id),
        do: MapSet.delete(active, id),
        else: MapSet.put(active, id)

    {:noreply, assign(socket, :active_leagues, active)}
  end

  def handle_event("all_leagues", _params, socket) do
    all = MapSet.new(socket.assigns.overview, fn {competition, _} -> competition.id end)
    {:noreply, assign(socket, :active_leagues, all)}
  end

  def handle_event("no_leagues", _params, socket) do
    {:noreply, assign(socket, :active_leagues, MapSet.new())}
  end

  ## Schnellauswahl – wirkt nur auf die vorgewaehlten Ligen

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

  def handle_event("toggle_competition", %{"id" => id}, socket) do
    kit_ids = competition_kit_ids(socket, String.to_integer(id))
    ranking = socket.assigns.ranking

    # Alles-oder-nichts: sind schon alle drin, nimmt der Knopf sie wieder raus.
    if Enum.all?(kit_ids, &MapSet.member?(socket.assigns.selected, &1)) do
      Enum.each(kit_ids, &Rankings.remove_kit(ranking, &1))
    else
      Rankings.add_kits(ranking, kit_ids)
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

  defp competition_kit_ids(socket, competition_id) do
    socket.assigns.overview
    |> Enum.find(fn {competition, _teams} -> competition.id == competition_id end)
    |> case do
      nil -> []
      {_competition, teams} -> for {_team, kits} <- teams, kit <- kits, do: kit.id
    end
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
          overview={@overview}
          selected={@selected}
          active_leagues={@active_leagues}
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

  attr :overview, :list, required: true
  attr :selected, :any, required: true
  attr :active_leagues, :any, required: true

  defp selection(assigns) do
    assigns =
      assign(
        assigns,
        :scoped,
        Enum.filter(assigns.overview, fn {c, _} ->
          MapSet.member?(assigns.active_leagues, c.id)
        end)
      )

    ~H"""
    <div
      :if={@overview == []}
      class="mt-10 rounded-lg border border-dashed border-line p-12 text-center"
    >
      <p class="text-sm text-soft">Für diese Saison sind noch keine Trikots hinterlegt.</p>
    </div>

    <div :if={@overview != []} class="mt-8 rounded-lg border border-line p-5">
      <div class="flex flex-wrap items-center gap-2">
        <h2 class="kr-eyebrow">Welche Ligen?</h2>
        <button
          type="button"
          phx-click="all_leagues"
          class="ml-auto text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
        >
          Alle
        </button>
        <button
          type="button"
          phx-click="no_leagues"
          class="text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
        >
          Keine
        </button>
      </div>

      <div class="mt-3 flex flex-wrap gap-2">
        <button
          :for={{competition, teams} <- @overview}
          type="button"
          phx-click="toggle_league"
          phx-value-id={competition.id}
          aria-pressed={to_string(MapSet.member?(@active_leagues, competition.id))}
          class={[
            "flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm transition",
            MapSet.member?(@active_leagues, competition.id) && "border-transparent bg-ink text-chalk",
            !MapSet.member?(@active_leagues, competition.id) &&
              "border-line text-soft hover:border-ink hover:text-ink"
          ]}
        >
          {competition.name}
          <span class="font-mono text-[10px] opacity-60">{length(teams)}</span>
        </button>
      </div>

      <div :if={@scoped != []} class="mt-5 border-t border-line pt-4">
        <div class="flex flex-wrap items-baseline gap-2">
          <h3 class="kr-eyebrow">Schnell auswählen</h3>
          <span class="text-[11px] text-soft">wirkt nur auf {league_names(@scoped)}</span>
        </div>
        <div class="mt-3 flex flex-wrap gap-2">
          <.quick_button
            :for={type <- available_types(@scoped)}
            type={type}
            label={Kit.label(type)}
            all_selected?={type_all_selected?(@scoped, @selected, type)}
          />
          <.quick_button
            type="all"
            label="Trikots"
            all_selected?={type_all_selected?(@scoped, @selected, "all")}
          />
        </div>
      </div>
    </div>

    <div
      :if={@overview != [] && @scoped == []}
      class="mt-8 rounded-lg border border-dashed border-line p-12 text-center"
    >
      <p class="kr-display text-xl">Erst eine Liga wählen</p>
      <p class="mx-auto mt-2 max-w-sm text-sm text-soft">
        Dann erscheinen hier die Trikots, und die Schnellauswahl weiß, worauf sie sich bezieht.
      </p>
    </div>

    <section :for={{competition, teams} <- @scoped} class="mt-10">
      <div class="flex flex-wrap items-baseline gap-3 border-b border-line pb-2">
        <h2 class="kr-display text-lg">{competition.name}</h2>
        <span class="kr-eyebrow">{competition.country} · Liga {competition.tier}</span>
        <button
          type="button"
          phx-click="toggle_competition"
          phx-value-id={competition.id}
          class="ml-auto rounded-md border border-line px-3 py-1 font-mono text-[11px] text-soft transition hover:border-ink hover:text-ink"
        >
          {if all_selected?(teams, @selected), do: "Alle abwählen", else: "Alle auswählen"}
        </button>
      </div>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
        <%= for {team, kits} <- teams, kit <- kits do %>
          <.pick_tile kit={kit} team={team} selected={MapSet.member?(@selected, kit.id)} />
        <% end %>
      </div>
    </section>
    """
  end

  defp all_selected?(teams, selected) do
    kits = for {_team, kits} <- teams, kit <- kits, do: kit.id
    kits != [] and Enum.all?(kits, &MapSet.member?(selected, &1))
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
  defp scoped_kit_ids(socket, "all") do
    for {competition, teams} <- socket.assigns.overview,
        MapSet.member?(socket.assigns.active_leagues, competition.id),
        {_team, kits} <- teams,
        kit <- kits,
        do: kit.id
  end

  defp scoped_kit_ids(socket, kit_type) do
    for {competition, teams} <- socket.assigns.overview,
        MapSet.member?(socket.assigns.active_leagues, competition.id),
        {_team, kits} <- teams,
        kit <- kits,
        kit.kit_type == kit_type,
        do: kit.id
  end

  defp league_names(scoped) do
    scoped |> Enum.map(fn {competition, _} -> competition.name end) |> to_sentence()
  end

  defp to_sentence([one]), do: one
  defp to_sentence([a, b]), do: "#{a} und #{b}"
  defp to_sentence(names), do: Enum.join(names, ", ")

  # Nur Kit-Typen anbieten, die es in den gewaehlten Ligen ueberhaupt gibt –
  # ein Knopf "Sonder", der nichts tut, waere nur Rauschen.
  defp available_types(scoped) do
    vorhanden =
      for {_competition, teams} <- scoped,
          {_team, kits} <- teams,
          kit <- kits,
          into: MapSet.new(),
          do: kit.kit_type

    Enum.filter(Kit.kit_types(), &MapSet.member?(vorhanden, &1))
  end

  defp type_all_selected?(scoped, selected, type) do
    ids =
      for {_competition, teams} <- scoped,
          {_team, kits} <- teams,
          kit <- kits,
          type == "all" or kit.kit_type == type,
          do: kit.id

    ids != [] and Enum.all?(ids, &MapSet.member?(selected, &1))
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
      size="max-w-3xl"
    >
      <div class="grid gap-0 sm:grid-cols-2">
        <div>
          <div
            class="flex aspect-square items-center justify-center rounded-tl-xl p-6 sm:p-10"
            style={"background-color: color-mix(in oklab, #{@color} 13%, #FFFFFF)"}
          >
            <.kit_figure
              kit={@entry.kit}
              team={@entry.kit.team}
              image_url={@src}
              class="h-full w-full"
            />
          </div>

          <div :if={length(@images) > 1} class="flex gap-1.5 border-t border-line px-4 py-2.5">
            <button
              :for={{_url, i} <- Enum.with_index(@images)}
              type="button"
              phx-click="detail_image"
              phx-value-index={i}
              class={[
                "h-1.5 flex-1 rounded-full transition",
                i == @image && "bg-ink",
                i != @image && "bg-line hover:bg-soft"
              ]}
              aria-label={"Bild #{i + 1} von #{length(@images)} zeigen"}
              aria-current={to_string(i == @image)}
            />
          </div>
        </div>

        <div class="flex flex-col border-t border-line p-5 sm:border-l sm:border-t-0">
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
