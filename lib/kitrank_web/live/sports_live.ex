defmodule KitrankWeb.SportsLive do
  @moduledoc """
  Die Startseite: welche Sportart?

  Vorher standen alle Ligen aller Sportarten auf einer Seite. Mit zwei
  Sportarten, drei Ligen und 68 Vereinen ging das nur noch zugeklappt — eine
  Notlösung für ein Struktur-Problem. Die Sportart ist die erste Frage, also
  steht sie hier und nicht als weiteres Filterband über einem langen Raster.

  Gezeigt werden nur Sportarten, die in der Saison wirklich Vereine haben. Eine
  Kachel, die auf eine leere Seite führt, ist schlimmer als keine Kachel.
  """
  use KitrankWeb, :live_view

  alias Kitrank.Kits

  @impl true
  def mount(_params, _session, socket) do
    seasons = Kits.list_seasons()
    season = List.first(seasons) || Kits.current_season()

    {:ok,
     socket
     |> assign(page_title: gettext("Übersicht"), season: season)
     |> assign(:sports, Kits.list_sports_for_season(season))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-[1100px] px-4 pb-32 pt-10 sm:px-6 lg:px-8">
        <%!-- Zwei Wege nebeneinander, nicht einer im Text und einer in der
            Navigation: allein stoebern steht links und geht unten weiter, das
            Reveal steht rechts als eigener Kasten. Es ist das, was diese App
            kann und trikotranking.de nicht — in einer Ecke der Kopfzeile war
            es dafuer zu leise. --%>
        <div class="grid items-start gap-8 border-b border-line pb-10 md:grid-cols-[1fr_auto]">
          <div>
            <p class="kr-eyebrow">{gettext("Saison %{jahr}", jahr: @season)}</p>
            <h1 class="kr-display mt-2 max-w-[14ch] text-4xl leading-[0.95] text-balance sm:text-5xl">
              {gettext("Welches Trikot ist das schönste?")}
            </h1>
            <p class="mt-4 max-w-md text-sm leading-relaxed text-soft">
              {gettext("Such dir unten eine Sportart aus — oder bau gleich")}
              <.link navigate={~p"/rankings/new"} class="text-ink underline underline-offset-4">
                {gettext("eine eigene Rangliste")}
              </.link>.
            </p>
          </div>

          <%!-- Dunkel, weil alles andere auf dieser Seite hell ist: der
                Unterschied soll man sehen, bevor man ihn liest. --%>
          <div class="rounded-xl bg-ink p-6 text-chalk md:max-w-sm">
            <p class="kr-eyebrow !text-chalk/60">{gettext("Zu mehreren")}</p>
            <h2 class="kr-display mt-2 text-2xl leading-tight">
              {gettext("Zusammen aufdecken")}
            </h2>
            <p class="mt-3 text-sm leading-relaxed text-chalk/75">
              {gettext(
                "Jede:r baut seine eigene Liste. Dann dreht ihr Platz für Platz um, alle Geräte gleichzeitig — und seht, wo ihr euch einig seid und wo überhaupt nicht."
              )}
            </p>
            <.link
              navigate={~p"/reveal/new"}
              data-role="reveal-hero"
              class="mt-5 inline-block rounded-md bg-chalk px-5 py-2.5 text-sm font-semibold text-ink transition hover:opacity-90"
            >
              {gettext("Reveal starten oder beitreten")}
            </.link>
          </div>
        </div>

        <div
          :if={@sports == []}
          class="mt-16 rounded-lg border border-dashed border-line p-12 text-center"
        >
          <p class="kr-display text-xl">
            {gettext("Noch keine Trikots für %{saison}", saison: @season)}
          </p>
          <p class="mx-auto mt-2 max-w-md text-sm text-soft">
            {gettext("Trag Ligen, Teams und Trikots im Admin ein — dann füllt sich diese Seite.")}
          </p>
        </div>

        <div class="mt-8 grid gap-4 sm:grid-cols-2">
          <.sport_card :for={eintrag <- @sports} entry={eintrag} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true

  defp sport_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@entry.sport.slug}"}
      data-role="sport-card"
      class="group flex flex-col justify-between rounded-xl border border-line bg-panel p-6 transition hover:border-ink hover:shadow-[0_10px_32px_-18px_rgb(0_0_0/0.5)]"
    >
      <div>
        <h2 class="kr-display text-2xl leading-none">{@entry.sport.name}</h2>
        <p class="mt-2 font-mono text-xs text-soft">
          {ngettext("%{anzahl} Liga", "%{anzahl} Ligen", @entry.competition_count,
            anzahl: @entry.competition_count
          )}
          <span class="px-1">·</span>
          {ngettext("%{anzahl} Verein", "%{anzahl} Vereine", @entry.team_count,
            anzahl: @entry.team_count
          )}
        </p>
      </div>

      <%!-- Ein Streifen aus den Vereinsfarben statt eines Symbols: die App hat
            keine Logos und will keine, und die Farben sind das, woran man eine
            Liga erkennt. --%>
      <div :if={@entry.colors != []} class="mt-6 flex h-1.5 gap-0.5 overflow-hidden rounded-full">
        <span
          :for={farbe <- @entry.colors}
          class="flex-1"
          style={"background-color: #{farbe}"}
        />
      </div>

      <span class="mt-4 font-mono text-[11px] text-soft transition group-hover:text-ink">
        {gettext("Ansehen")} →
      </span>
    </.link>
    """
  end
end
