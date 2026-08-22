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
           share_url: url(~p"/r/#{ranking.share_slug}")
         )
         |> load_entries()}
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

  ## Auswahl

  @impl true
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
        />

        <.sorting
          :if={@live_action == :sort}
          entries={@entries}
          edit_token={@ranking.edit_token}
        />
      </div>

      <.step_bar live_action={@live_action} edit_token={@ranking.edit_token} count={@count} />
    </Layouts.app>
    """
  end

  ## Auswahl-Ansicht

  attr :overview, :list, required: true
  attr :selected, :any, required: true

  defp selection(assigns) do
    ~H"""
    <div
      :if={@overview == []}
      class="mt-10 rounded-lg border border-dashed border-line p-12 text-center"
    >
      <p class="text-sm text-soft">Für diese Saison sind noch keine Trikots hinterlegt.</p>
    </div>

    <section :for={{competition, teams} <- @overview} class="mt-10">
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
      />
    </ul>

    <p :if={@entries != []} class="mt-4 text-xs text-soft">
      Ziehen am Griff sortiert um. Ohne Maus gehen auch die Pfeile — beides speichert sofort.
    </p>
    """
  end
end
