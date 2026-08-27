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
  alias Kitrank.Reveal

  @impl true
  def mount(_params, _session, socket) do
    seasons = Kits.list_seasons()
    season = List.first(seasons) || Kits.current_season()

    {:ok,
     socket
     |> assign(page_title: gettext("Übersicht"), season: season, code_error: nil)
     |> assign(:sports, Kits.list_sports_for_season(season))}
  end

  @doc """
  Mit einem Raumcode direkt in den Raum.

  Der haeufigere Reveal-Fall ist nicht „ich starte einen Raum", sondern „ich
  habe einen Code im Chat bekommen". Der Weg dafuer war Hero → /reveal/new →
  Feld; jetzt ist er ein Feld.

  Beigetreten wird weiterhin erst im Raum — hier wird nur nachgeschlagen und
  weitergeleitet. Das ist keine zweite Beitreten-Logik, sondern derselbe
  Sprung, den /reveal/new auch macht.
  """
  @impl true
  def handle_event("join_reveal", %{"room_code" => code}, socket) do
    case Reveal.fetch_room(code) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/reveal/#{room.room_code}")}

      {:error, :expired} ->
        {:noreply, assign(socket, :code_error, gettext("Dieser Raum ist abgelaufen."))}

      {:error, :not_found} ->
        {:noreply,
         assign(socket, :code_error, gettext("Diesen Code kennen wir nicht. Vertippt?"))}
    end
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
            <%!-- Der Code zuerst, das Erstellen als Nebensatz: die meisten
                  kommen mit einem Code aus einer Nachricht, nicht mit der
                  Absicht, einen Raum aufzumachen. --%>
            <form phx-submit="join_reveal" id="reveal-code" class="mt-5 flex gap-2">
              <label for="room_code" class="sr-only">{gettext("Raumcode")}</label>
              <input
                type="text"
                id="room_code"
                name="room_code"
                maxlength="5"
                autocomplete="off"
                autocapitalize="characters"
                placeholder={gettext("ABC23")}
                class="w-28 rounded-md border border-chalk/25 bg-chalk/10 px-3 py-2 text-center font-mono text-sm uppercase tracking-[0.15em] text-chalk placeholder:text-chalk/35 focus:border-chalk focus:outline-none"
              />
              <button
                type="submit"
                data-role="reveal-join"
                class="rounded-md bg-chalk px-4 py-2 text-sm font-semibold text-ink transition hover:opacity-90"
              >{gettext("Beitreten")}</button>
            </form>

            <p :if={@code_error} class="mt-2 text-xs text-red-300">{@code_error}</p>

            <p class="mt-3 text-xs text-chalk/60">
              {gettext("Noch kein Raum?")}
              <.link
                navigate={~p"/reveal/new"}
                data-role="reveal-hero"
                class="text-chalk underline underline-offset-4"
              >{gettext("Einen aufmachen")}</.link>.
            </p>
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

      <%!-- Ein Strich je Verein, in Vereinsfarbe. Kein Symbol: die App hat
            keine Logos und will keine, und die Farben sind das, woran man eine
            Liga erkennt. So viele Striche wie Vereine — der Streifen sagt
            damit dasselbe wie die Zahl darueber, nur sichtbar. --%>
      <div
        :if={@entry.colors != []}
        class="mt-6 flex h-1.5 gap-px overflow-hidden rounded-full"
        role="img"
        aria-label={
          ngettext(
            "Ein Strich je Verein: %{anzahl}",
            "Ein Strich je Verein: %{anzahl}",
            @entry.team_count,
            anzahl: @entry.team_count
          )
        }
      >
        <span :for={farbe <- @entry.colors} class="flex-1" style={"background-color: #{farbe}"} />
      </div>

      <span class="mt-4 font-mono text-[11px] text-soft transition group-hover:text-ink">
        {gettext("Ansehen")} →
      </span>
    </.link>
    """
  end
end
