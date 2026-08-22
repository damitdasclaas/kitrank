defmodule KitrankWeb.Ranking.ShowLive do
  @moduledoc """
  Die öffentliche Ansicht einer Rangliste unter `/r/:share_slug`.

  Liest denselben Datensatz wie die Bearbeitung – es gibt keinen Export und
  keinen Veröffentlichen-Schritt. Wer den Link öffnet, sieht den Stand von
  jetzt.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.KitComponents

  alias Kitrank.Kits.Kit
  alias Kitrank.Rankings
  alias KitrankWeb.Color

  @impl true
  def mount(%{"share_slug" => slug}, _session, socket) do
    case Rankings.get_ranking_by_share_slug(slug) do
      nil ->
        raise KitrankWeb.NotFoundError, "Rangliste nicht gefunden"

      ranking ->
        entries = Rankings.list_entries(ranking)

        {:ok,
         assign(socket,
           page_title: ranking.display_name || "Rangliste",
           ranking: ranking,
           entries: entries,
           zoom: nil
         )}
    end
  end

  ## Grosse Ansicht

  @impl true
  def handle_event("zoom", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Enum.find(socket.assigns.entries, &(&1.kit_id == id)) do
      nil -> {:noreply, socket}
      entry -> {:noreply, assign(socket, :zoom, %{kit: entry.kit, index: 0})}
    end
  end

  def handle_event("zoom_close", _params, socket), do: {:noreply, assign(socket, :zoom, nil)}

  def handle_event("zoom_step", %{"delta" => delta}, socket) do
    {:noreply, step_zoom(socket, String.to_integer(delta))}
  end

  def handle_event("zoom_key", %{"key" => key}, socket) do
    case key do
      "Escape" -> {:noreply, assign(socket, :zoom, nil)}
      "ArrowLeft" -> {:noreply, step_zoom(socket, -1)}
      "ArrowRight" -> {:noreply, step_zoom(socket, 1)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  defp step_zoom(%{assigns: %{zoom: nil}} = socket, _delta), do: socket

  defp step_zoom(%{assigns: %{zoom: zoom}} = socket, delta) do
    count = zoom.kit |> kit_images() |> length()

    if count <= 1 do
      socket
    else
      assign(socket, :zoom, %{zoom | index: Integer.mod(zoom.index + delta, count)})
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-4 py-12 sm:px-6">
        <p class="kr-eyebrow">
          Rangliste · {length(@entries)} {if length(@entries) == 1, do: "Trikot", else: "Trikots"}
        </p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">
          {@ranking.display_name || "Ohne Namen"}
        </h1>

        <div
          :if={@entries == []}
          class="mt-10 rounded-lg border border-dashed border-line p-12 text-center"
        >
          <p class="text-sm text-soft">Diese Rangliste ist noch leer.</p>
        </div>

        <ol :if={@entries != []} class="mt-10 space-y-3">
          <.row :for={{entry, index} <- Enum.with_index(@entries)} entry={entry} index={index} />
        </ol>

        <div class="mt-14 border-t border-line pt-6">
          <p class="text-sm text-soft">
            Eigene Rangliste bauen?
            <.link navigate={~p"/rankings/new"} class="text-ink underline underline-offset-4">
              Hier entlang
            </.link>
            — oder erst mal <.link navigate={~p"/"} class="text-ink underline underline-offset-4">
              alle Trikots ansehen
            </.link>.
          </p>
        </div>
      </div>

      <.kit_lightbox
        :if={@zoom}
        kit={@zoom.kit}
        team={@zoom.kit.team}
        images={kit_images(@zoom.kit)}
        index={@zoom.index}
        label={Kit.label(@zoom.kit.kit_type)}
      />
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true
  attr :index, :integer, required: true

  defp row(assigns) do
    assigns = assign(assigns, :color, Color.team_color(assigns.entry.kit.team))

    ~H"""
    <li class="flex items-start gap-4">
      <span class="kr-display w-9 shrink-0 pt-3 text-right text-2xl tabular-nums leading-none">
        {@index + 1}
      </span>

      <div class="min-w-0 flex-1 rounded-lg border border-line bg-panel p-3">
        <div class="flex items-start gap-3">
          <button
            type="button"
            phx-click="zoom"
            phx-value-id={@entry.kit_id}
            class="group relative flex h-20 w-20 shrink-0 cursor-zoom-in items-center justify-center rounded-md"
            style={"background-color: color-mix(in oklab, #{@color} 14%, #FFFFFF)"}
            aria-label={"#{@entry.kit.team.name} #{Kit.label(@entry.kit.kit_type)} gross ansehen"}
          >
            <.kit_figure
              kit={@entry.kit}
              team={@entry.kit.team}
              class="h-16 w-16 transition-transform duration-300 group-hover:scale-105"
              size={:thumb}
            />
            <.zoom_hint class="!bottom-1 !right-1 !h-5 !w-5" />
          </button>

          <div class="min-w-0 flex-1">
            <p class="flex flex-wrap items-baseline gap-x-2">
              <span class="font-mono text-xs font-semibold" style={"color: #{@color}"}>
                {@entry.kit.team.short_code}
              </span>
              <span class="text-sm font-medium">{@entry.kit.team.name}</span>
              <span class="text-xs text-soft">{Kit.label(@entry.kit.kit_type)}</span>
            </p>

            <p :if={@entry.note} class="mt-1.5 text-sm leading-relaxed text-soft">
              {@entry.note}
            </p>

            <a
              :if={@entry.kit.source_shop_url}
              href={@entry.kit.source_shop_url}
              target="_blank"
              rel="noopener noreferrer"
              class="mt-2 inline-flex items-center gap-1 text-[11px] text-soft underline underline-offset-4 hover:text-ink"
            >
              Im Shop ansehen <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
            </a>
          </div>
        </div>
      </div>
    </li>
    """
  end
end
