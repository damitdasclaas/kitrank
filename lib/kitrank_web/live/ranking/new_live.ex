defmodule KitrankWeb.Ranking.NewLive do
  @moduledoc """
  Eine neue Rangliste anlegen. Kein Konto nötig – es entstehen zwei Links, und
  wer sie hat, darf damit etwas.
  """
  use KitrankWeb, :live_view

  alias Kitrank.Kits
  alias Kitrank.Rankings

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()

    {:ok,
     assign(socket,
       page_title: "Neue Rangliste",
       season: season,
       kit_count: length(Kits.list_rankable_kits(season)),
       form: to_form(Rankings.change_ranking(%Rankings.Ranking{})),
       remembered: []
     )}
  end

  @doc """
  Nimmt die im Browser gemerkten Ranglisten entgegen und schlaegt sie nach.

  Der Browser kennt nur Tokens; welche davon es noch gibt und wie sie heissen,
  weiss nur der Server. Verschwundene werden gleich wieder aus dem Browser
  geworfen, damit dort keine toten Links liegenbleiben.
  """
  @impl true
  def handle_event("remembered_rankings", %{"tokens" => tokens}, socket) when is_list(tokens) do
    gefunden =
      tokens
      |> Enum.take(20)
      |> Enum.map(&Rankings.get_ranking_by_edit_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn ranking ->
        %{ranking: ranking, count: Rankings.count_entries(ranking.id)}
      end)

    {:noreply,
     socket
     |> assign(:remembered, gefunden)
     |> push_event("prune_rankings", %{keep: Enum.map(gefunden, & &1.ranking.edit_token)})}
  end

  def handle_event("forget", %{"token" => token}, socket) do
    {:noreply,
     socket
     |> assign(
       :remembered,
       Enum.reject(socket.assigns.remembered, &(&1.ranking.edit_token == token))
     )
     |> push_event("forget_ranking", %{token: token})}
  end

  @impl true
  def handle_event("save", %{"ranking" => attrs}, socket) do
    case Rankings.create_ranking(attrs) do
      {:ok, ranking} ->
        # Leere Rangliste – der erste Schritt ist die Auswahl, nicht das Sortieren.
        {:noreply, push_navigate(socket, to: ~p"/rankings/#{ranking.edit_token}/auswahl")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl px-4 py-16 sm:px-6">
        <p class="kr-eyebrow">Saison {@season}</p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">Deine Ranglisten</h1>
        <p class="mt-4 text-sm leading-relaxed text-soft">
          Such dir aus {@kit_count} Trikots die aus, über die du etwas zu sagen hast,
          und bring sie in eine Reihenfolge. Kein Konto nötig.
        </p>

        <div id="remembered" phx-hook="RememberedRankings" class="mt-8">
          <div :if={@remembered != []} class="rounded-lg border border-line">
            <h2 class="kr-eyebrow border-b border-line px-4 py-3">In diesem Browser gemerkt</h2>
            <ul>
              <li
                :for={%{ranking: ranking, count: count} <- @remembered}
                class="flex items-center gap-3 border-b border-line px-4 py-3 last:border-0"
              >
                <.link
                  navigate={~p"/rankings/#{ranking.edit_token}/edit"}
                  class="min-w-0 flex-1"
                >
                  <span class="block truncate text-sm font-medium">
                    {ranking.display_name || "Ohne Namen"}
                  </span>
                  <span class="font-mono text-[11px] text-soft">
                    {count} {if count == 1, do: "Trikot", else: "Trikots"}
                  </span>
                </.link>
                <.link
                  navigate={~p"/r/#{ranking.share_slug}"}
                  class="shrink-0 text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
                >
                  Teilen-Ansicht
                </.link>
                <button
                  type="button"
                  phx-click="forget"
                  phx-value-token={ranking.edit_token}
                  class="shrink-0 text-[11px] text-soft underline-offset-4 hover:text-ink hover:underline"
                >
                  Vergessen
                </button>
              </li>
            </ul>
            <p class="px-4 py-3 text-xs text-soft">
              Nur in diesem Browser. Auf einem anderen Gerät brauchst du den Bearbeiten-Link.
            </p>
          </div>
        </div>

        <.form for={@form} id="new-ranking" phx-submit="save" class="mt-8">
          <.input
            field={@form[:display_name]}
            label="Name der Rangliste"
            placeholder="Toms Rangliste"
          />
          <p class="mt-1.5 text-xs text-soft">
            Optional. Steht später über deiner Liste und im Reveal neben deinem Namen.
          </p>

          <button
            type="submit"
            phx-disable-with="Wird angelegt …"
            class="mt-6 w-full rounded-md bg-ink px-4 py-3 text-sm font-semibold text-chalk transition hover:opacity-90"
          >
            Trikots auswählen
          </button>
        </.form>

        <div class="mt-10 rounded-lg border border-line p-5">
          <h2 class="kr-eyebrow">Wie der Zugriff funktioniert</h2>
          <ul class="mt-3 space-y-2 text-sm text-soft">
            <li>
              <span class="text-ink">Bearbeiten-Link</span> — geheim. Wer ihn hat, kann deine
              Rangliste ändern. Leg ihn dir als Lesezeichen an.
            </li>
            <li>
              <span class="text-ink">Teilen-Link</span> — öffentlich und nur zum Lesen. Er zeigt
              immer den aktuellen Stand, du musst nichts erneut verschicken.
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
