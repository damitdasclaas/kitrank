defmodule KitrankWeb.Ranking.ShowLive do
  @moduledoc """
  Die öffentliche Ansicht einer Rangliste unter `/r/:share_slug`.

  Liest denselben Datensatz wie die Bearbeitung – es gibt keinen Export und
  keinen Veröffentlichen-Schritt. Wer den Link öffnet, sieht den Stand von
  jetzt.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.KitComponents

  alias Kitrank.Accounts
  alias Kitrank.Rankings
  alias Kitrank.Rankings.Ranking
  alias Kitrank.Reveal.Result
  alias KitrankWeb.Color
  alias KitrankWeb.KitLabel

  @impl true
  def mount(%{"share_slug" => slug}, _session, socket) do
    case Rankings.get_ranking_by_share_slug(slug) do
      nil ->
        raise KitrankWeb.NotFoundError, gettext("Rangliste nicht gefunden")

      ranking ->
        {:ok,
         assign(socket,
           page_title: ranking.display_name || gettext("Rangliste"),
           ranking: ranking,
           entries: Rankings.list_entries(ranking),
           zoom: nil,
           # Bei „erst selbst ranken" weiss der Server noch nicht, ob dieser
           # Browser schon eine eigene Liste hat – danach fragt er gleich.
           gate: if(Ranking.gated?(ranking), do: :unknown, else: :open),
           eigene: nil,
           vergleich: nil
         )}
    end
  end

  ## Das Gate

  # Der Browser meldet, welche Ranglisten er sich gemerkt hat. Mehr Nachweis
  # gibt es ohne Login nicht — siehe Rankings.gate_state/2.
  @impl true
  def handle_event("remembered_rankings", %{"tokens" => tokens}, socket) do
    ranking = socket.assigns.ranking

    case Rankings.gate_state(ranking, tokens) do
      {:passed, eigene} ->
        {:noreply,
         assign(socket,
           gate: :passed,
           eigene: eigene,
           vergleich: vergleich(ranking, eigene)
         )}

      {:building, eigene} ->
        {:noreply, assign(socket, gate: :building, eigene: eigene)}

      :none ->
        {:noreply, assign(socket, gate: :blocked, eigene: nil)}
    end
  end

  def handle_event("start_own", _params, socket) do
    {:ok, eigene} = Rankings.create_derived(socket.assigns.ranking)

    {:noreply, push_navigate(socket, to: ~p"/rankings/#{eigene.edit_token}/auswahl")}
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

  # Dieselbe Auswertung wie im Reveal. Sie rechnet ueber Ranglisten und weiss
  # nichts von Raeumen — zwei Listen sind der kleinste Fall davon, und es waere
  # unsinnig, daneben eine zweite Vergleichsrechnung zu bauen.
  defp vergleich(original, eigene) do
    teilnehmer = [
      %{id: eigene.id, display_name: gettext("Deine Liste")},
      %{id: original.id, display_name: original.display_name || gettext("Die geteilte Liste")}
    ]

    Result.build(teilnehmer, %{
      eigene.id => Rankings.list_entries(eigene),
      original.id => Rankings.list_entries(original)
    })
  end

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
          {ngettext("Rangliste · %{count} Trikot", "Rangliste · %{count} Trikots", length(@entries))}
        </p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">
          {@ranking.display_name || "Ohne Namen"}
        </h1>

        <%!-- Fragt den Browser nach seinen gemerkten Ranglisten. Nur bei
              „erst selbst ranken" – sonst gibt es nichts nachzuweisen. --%>
        <div :if={Ranking.gated?(@ranking)} id="gate" phx-hook="RememberedRankings" hidden></div>

        <.gate_screen :if={@gate in [:unknown, :blocked, :building]} gate={@gate} eigene={@eigene} />

        <div :if={@gate in [:open, :passed]}>
          <div
            :if={@entries == []}
            class="mt-10 rounded-lg border border-dashed border-line p-12 text-center"
          >
            <p class="text-sm text-soft">{gettext("Diese Rangliste ist noch leer.")}</p>
          </div>

          <.vergleich_kopf :if={@vergleich} vergleich={@vergleich} eigene={@eigene} />

          <ol :if={@entries != []} class="mt-10 space-y-3">
            <.row :for={{entry, index} <- Enum.with_index(@entries)} entry={entry} index={index} />
          </ol>
        </div>

        <div class="mt-14 border-t border-line pt-6">
          <p class="text-sm text-soft">
            {gettext("Eigene Rangliste bauen?")}
            <.link navigate={~p"/rankings/new"} class="text-ink underline underline-offset-4">{gettext(
              "Hier entlang"
            )}</.link> {gettext("— oder erst mal")} <.link
              navigate={~p"/"}
              class="text-ink underline underline-offset-4"
            > {gettext("alle Trikots ansehen")} </.link>.
          </p>
        </div>
      </div>

      <.kit_lightbox
        :if={@zoom}
        kit={@zoom.kit}
        team={@zoom.kit.team}
        images={kit_images(@zoom.kit)}
        index={@zoom.index}
        label={KitLabel.display(@zoom.kit)}
      />
    </Layouts.app>
    """
  end

  attr :gate, :atom, required: true
  attr :eigene, :any, required: true

  # Der Bildschirm vor der fremden Liste.
  #
  # Der Punkt der Sperre ist die Reihenfolge: wer die fremde Liste vorher
  # sieht, rankt nicht mehr unbefangen. Deshalb steht hier auch, worum es geht,
  # und nicht nur „geht nicht".
  defp gate_screen(assigns) do
    ~H"""
    <div class="mt-10 rounded-lg border border-line bg-sunk p-8 sm:p-10">
      <div :if={@gate == :unknown} class="text-sm text-soft">
        {gettext("Einen Moment …")}
      </div>

      <div :if={@gate == :blocked}>
        <p class="kr-eyebrow">{gettext("Erst du, dann sie")}</p>
        <h2 class="kr-display mt-2 text-2xl leading-tight">
          {gettext("Diese Liste zeigt sich erst, wenn du selbst gerankt hast.")}
        </h2>
        <p class="mt-3 max-w-lg text-sm leading-relaxed text-soft">
          {gettext(
            "So war es gemeint: wer die fremde Reihenfolge vorher sieht, sortiert nicht mehr unbefangen. Du bekommst genau denselben Ausschnitt — dieselben Vereine, dieselben Trikots."
          )}
        </p>
        <button
          type="button"
          phx-click="start_own"
          data-role="start-own"
          class="mt-6 rounded-md bg-ink px-5 py-2.5 text-sm font-semibold text-chalk transition hover:opacity-90"
        >{gettext("Eigene Rangliste bauen")}</button>
      </div>

      <div :if={@gate == :building}>
        <p class="kr-eyebrow">{gettext("Fast")}</p>
        <h2 class="kr-display mt-2 text-2xl leading-tight">
          {gettext("Deine Liste ist noch nicht fertig.")}
        </h2>
        <p class="mt-3 max-w-lg text-sm leading-relaxed text-soft">
          {gettext("Jedes Trikot des Ausschnitts braucht einen Platz — dann wird beides gezeigt.")}
        </p>
        <.link
          :if={@eigene}
          navigate={~p"/rankings/#{@eigene.edit_token}/edit"}
          class="mt-6 inline-block rounded-md bg-ink px-5 py-2.5 text-sm font-semibold text-chalk transition hover:opacity-90"
        >{gettext("Weitermachen")}</.link>
      </div>

      <%!-- Die ehrliche Einschraenkung, nicht kleingedruckt: die Sperre haengt
            am localStorage dieses Browsers. --%>
      <p :if={@gate != :unknown} class="mt-6 border-t border-line pt-4 text-xs text-soft">
        {gettext(
          "Gemerkt wird das in diesem Browser. In einem privaten Fenster oder auf einem anderen Gerät fängt es von vorn an."
        )}
        <%!-- Das Angebot nur, wenn es auch eingeloest werden kann. Ein Link auf
              eine geschlossene Registrierung waere eine Sackgasse. --%>
        <.link
          :if={Accounts.registration_open?()}
          navigate={~p"/users/register"}
          class="text-ink underline underline-offset-4"
        >{gettext("Mit einem Konto findest du deine Listen überall wieder.")}</.link>
      </p>
    </div>
    """
  end

  attr :vergleich, :map, required: true
  attr :eigene, :map, required: true

  # Der Lohn fuer die Muehe: nicht nur die fremde Liste, sondern der Vergleich.
  # Gerechnet wird er von derselben Auswertung wie im Reveal.
  defp vergleich_kopf(assigns) do
    ~H"""
    <div class="mt-10 rounded-lg border border-line p-6">
      <p class="kr-eyebrow">{gettext("Ihr beide")}</p>
      <p class="mt-2 text-sm text-soft">
        {ngettext(
          "%{anzahl} Trikot habt ihr beide einsortiert.",
          "%{anzahl} Trikots habt ihr beide einsortiert.",
          @vergleich.shared_count,
          anzahl: @vergleich.shared_count
        )}
      </p>

      <div :if={@vergleich.biggest_split} class="mt-4 rounded-md bg-sunk p-4">
        <p class="kr-eyebrow">{gettext("Größter Streitpunkt")}</p>
        <p class="mt-1.5 text-sm">
          {@vergleich.biggest_split.kit.team.name}
          <span class="text-soft">{KitLabel.display(@vergleich.biggest_split.kit)}</span>
          <span class="text-soft">
            — {Enum.map_join(@vergleich.biggest_split.positions, ", ", fn p ->
              "#{p.participant_name}: #{p.position}"
            end)}
          </span>
        </p>
      </div>

      <div :if={@vergleich.consensus_top != []} class="mt-4">
        <p class="kr-eyebrow">{gettext("Darauf konntet ihr euch einigen")}</p>
        <ol class="mt-1.5 space-y-1">
          <li :for={eintrag <- @vergleich.consensus_top} class="text-sm">
            {eintrag.kit.team.name}
            <span class="text-soft">{KitLabel.display(eintrag.kit)}</span>
          </li>
        </ol>
      </div>

      <p class="mt-5 border-t border-line pt-4 text-xs text-soft">
        <.link
          navigate={~p"/rankings/#{@eigene.edit_token}/edit"}
          class="text-ink underline underline-offset-4"
        >{gettext("Deine eigene Liste")}</.link>
        {gettext("steht darunter zum Weiterarbeiten bereit.")}
      </p>
    </div>
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
            aria-label={
              gettext("%{verein} %{trikot} groß ansehen",
                verein: @entry.kit.team.name,
                trikot: KitLabel.display(@entry.kit)
              )
            }
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
              <span class="text-xs text-soft">{KitLabel.display(@entry.kit)}</span>
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
              {gettext("Zum Vereinsshop")}
              <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
            </a>
          </div>
        </div>
      </div>
    </li>
    """
  end
end
