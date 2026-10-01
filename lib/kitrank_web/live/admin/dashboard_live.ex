defmodule KitrankWeb.Admin.DashboardLive do
  @moduledoc """
  Einstieg in die Datenpflege: was ist da, und was fehlt noch.

  Die Lücken sind der eigentliche Zweck der Seite – ein Trikot ohne Bild oder
  Shop-Link fällt in der Übersicht nicht auf, hier schon.
  """
  use KitrankWeb, :live_view

  import KitrankWeb.Admin.Components

  alias Kitrank.Kits

  @impl true
  def mount(_params, _session, socket) do
    season = Kits.current_season()
    kits = Kits.list_kits(season)

    {:ok,
     assign(socket,
       page_title: "Admin",
       season: season,
       sports: length(Kits.list_sports()),
       competitions: length(Kits.list_competitions()),
       teams: length(Kits.list_teams()),
       team_seasons: length(Kits.list_team_seasons(season)),
       kits: length(kits),
       without_image: Enum.count(kits, &(&1.cutout_url in [nil, ""])),
       without_shop: Enum.count(kits, &(&1.source_shop_url in [nil, ""])),
       checking_images?: false,
       # Aus der Datenbank, nicht aus einem frischen Lauf – eine Markierung als
       # erledigt soll einen Seitenneuaufruf ueberleben, nicht nur die
       # laufende Sitzung.
       pruef_ergebnis: Kits.ImageFindings.list(),
       pruef_erledigt: 0,
       pruef_gesamt: 0
     )}
  end

  @impl true
  def handle_event("bilder_pruefen", _params, socket) do
    # start_async laeuft in einem eigenen Prozess – self() darin waere dieser
    # neue Prozess, nicht die LiveView. Die Pid vorher einfangen, damit der
    # Fortschritt hierher zurueckfindet.
    lv = self()

    {:noreply,
     socket
     |> assign(checking_images?: true, pruef_erledigt: 0, pruef_gesamt: 0)
     |> start_async(:bilder_pruefen, fn ->
       Kitrank.Kits.ImageCheck.run(
         log: fn _zeile -> :ok end,
         on_progress: fn erledigt, gesamt ->
           send(lv, {:bilder_pruefen_fortschritt, erledigt, gesamt})
         end
       )
     end)}
  end

  def handle_event("bilder_pruefen_umschalten", %{"id" => id}, socket) do
    Kits.ImageFindings.toggle(id)
    {:noreply, assign(socket, pruef_ergebnis: Kits.ImageFindings.list())}
  end

  @impl true
  def handle_info({:bilder_pruefen_fortschritt, erledigt, gesamt}, socket) do
    {:noreply, assign(socket, pruef_erledigt: erledigt, pruef_gesamt: gesamt)}
  end

  @impl true
  def handle_async(:bilder_pruefen, {:ok, auffaellig}, socket) do
    ergebnis = Kits.ImageFindings.sync(auffaellig)
    {:noreply, assign(socket, checking_images?: false, pruef_ergebnis: ergebnis)}
  end

  # Der Pruef-Prozess selbst ist gestorben – soll die Seite nicht mitreissen,
  # siehe KitLive.handle_async(:fetch_images, {:exit, ...}, ...) fuer denselben
  # Fall beim Bilder-Abruf.
  def handle_async(:bilder_pruefen, {:exit, grund}, socket) do
    require Logger
    Logger.warning("Bilder-Pruefung abgebrochen: #{inspect(grund)}")

    {:noreply,
     socket
     |> assign(checking_images?: false)
     |> put_flash(:error, "Die Prüfung ist abgebrochen. Nochmal versuchen?")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.admin_shell
        title="Datenpflege"
        subtitle={"Stand der Saison #{@season}."}
        current_path="/admin"
      >
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <.stat label="Sportarten" value={@sports} path={~p"/admin/sportarten"} />
          <.stat label="Ligen" value={@competitions} path={~p"/admin/ligen"} />
          <.stat label="Vereine" value={@teams} path={~p"/admin/vereine"} />
          <.stat
            label={"Zuordnungen #{@season}"}
            value={@team_seasons}
            path={~p"/admin/saison"}
            hint="Wer spielt diese Saison in welcher Liga"
          />
          <.stat label={"Trikots #{@season}"} value={@kits} path={~p"/admin/trikots"} />
        </div>

        <div :if={@kits > 0} class="mt-8 rounded-lg border border-line p-5">
          <h2 class="kr-eyebrow">Was noch fehlt</h2>
          <ul class="mt-3 space-y-2 text-sm">
            <li class="flex items-baseline gap-2">
              <span class="font-mono tabular-nums">{@without_image}</span>
              <span class="text-soft">
                Trikots ohne Bild — die Übersicht zeichnet sie so lange in den Vereinsfarben.
              </span>
            </li>
            <li class="flex items-baseline gap-2">
              <span class="font-mono tabular-nums">{@without_shop}</span>
              <span class="text-soft">Trikots ohne Shop-Link.</span>
            </li>
          </ul>
        </div>

        <div :if={@kits > 0} class="mt-8 rounded-lg border border-line p-5">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h2 class="kr-eyebrow">Bild- und Shop-Adressen</h2>
              <p class="mt-1 text-xs text-soft">
                Prüft jede gespeicherte Adresse per Abruf – Bilder werden nur verlinkt, nicht
                gehostet, ein Verein kann die Adresse jederzeit ändern oder abschalten.
              </p>
            </div>
            <button
              type="button"
              class="btn btn-sm shrink-0"
              phx-click="bilder_pruefen"
              disabled={@checking_images?}
            >
              {if @checking_images?, do: "Prüft …", else: "Jetzt prüfen"}
            </button>
          </div>

          <div :if={@checking_images?} class="mt-4">
            <div class="h-1.5 w-full overflow-hidden rounded-full bg-sunk">
              <div
                class="h-full rounded-full bg-ink transition-all duration-300"
                style={"width: #{prozent(@pruef_erledigt, @pruef_gesamt)}%"}
              >
              </div>
            </div>
            <p class="mt-1 text-xs text-soft">
              {if @pruef_gesamt > 0,
                do: "#{@pruef_erledigt} von #{@pruef_gesamt} geprüft …",
                else: "Adressen werden gezählt …"}
            </p>
          </div>

          <p :if={@pruef_ergebnis == []} class="mt-4 text-sm text-soft">
            Keine offenen Funde — entweder noch nie geprüft, oder beim letzten Lauf war alles
            erreichbar.
          </p>

          <div :if={@pruef_ergebnis != []} class="mt-4 space-y-5">
            <div :if={tot(@pruef_ergebnis) != []}>
              <h3 class="text-sm font-medium">
                {Enum.count(tot(@pruef_ergebnis), &(&1.status == "offen"))} wahrscheinlich tot
              </h3>
              <.finding_list findings={tot(@pruef_ergebnis)} />
            </div>

            <div :if={unklar(@pruef_ergebnis) != []}>
              <h3 class="text-sm font-medium text-soft">
                {Enum.count(unklar(@pruef_ergebnis), &(&1.status == "offen"))} unklar – vermutlich nur Bot-Abwehr
              </h3>
              <p class="mt-1 text-xs text-soft">
                Die Prüfung läuft von diesem Server aus, nicht aus einem Browser. Manche Shops
                blocken Server-Adressen grundsätzlich – das heißt nicht, dass der Link für
                Besucher kaputt ist. Kein Grund zum Nachbessern, nur weil es hier steht.
              </p>
              <.finding_list findings={unklar(@pruef_ergebnis)} />
            </div>
          </div>
        </div>

        <div :if={@team_seasons == 0} class="mt-8 rounded-lg border border-dashed border-line p-6">
          <p class="text-sm">
            Für {@season} ist noch kein Verein einer Liga zugeordnet — die Übersicht bleibt
            deshalb leer. Der Weg dahin: erst <.link
              navigate={~p"/admin/ligen"}
              class="underline underline-offset-4"
            >Ligen</.link>, dann <.link
              navigate={~p"/admin/vereine"}
              class="underline underline-offset-4"
            >Vereine</.link>, dann <.link
              navigate={~p"/admin/saison"}
              class="underline underline-offset-4"
            >Saison</.link>.
          </p>
        </div>
      </.admin_shell>
    </Layouts.app>
    """
  end

  defp tot(ergebnis), do: Enum.filter(ergebnis, &(&1.kategorie == "tot"))
  defp unklar(ergebnis), do: Enum.filter(ergebnis, &(&1.kategorie == "unklar"))

  defp prozent(_erledigt, 0), do: 0
  defp prozent(erledigt, gesamt), do: round(erledigt / gesamt * 100)

  attr :findings, :list, required: true

  defp finding_list(assigns) do
    ~H"""
    <ul class="mt-2 space-y-2 text-sm">
      <li
        :for={eintrag <- @findings}
        class={[
          "flex items-start justify-between gap-3 rounded border border-line p-2",
          eintrag.status == "erledigt" && "opacity-50"
        ]}
      >
        <div class={eintrag.status == "erledigt" && "line-through decoration-soft"}>
          <p>
            <span class="font-medium">{eintrag.kit.team.short_code}</span>
            · {eintrag.feld} · {eintrag.beschreibung}
          </p>
          <p class="mt-1 break-all text-xs text-soft">{eintrag.url}</p>
        </div>
        <div class="flex shrink-0 items-center gap-3">
          <.link
            navigate={~p"/admin/trikots/#{eintrag.kit.id}"}
            class="whitespace-nowrap text-xs font-medium underline underline-offset-4"
          >
            Bearbeiten
          </.link>
          <button
            type="button"
            class="whitespace-nowrap text-xs text-soft underline underline-offset-4"
            phx-click="bilder_pruefen_umschalten"
            phx-value-id={eintrag.id}
          >
            {if eintrag.status == "offen", do: "Erledigt", else: "Zurücksetzen"}
          </button>
        </div>
      </li>
    </ul>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :path, :string, required: true
  attr :hint, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="block rounded-lg border border-line p-5 transition hover:border-ink/30"
    >
      <p class="kr-eyebrow">{@label}</p>
      <p class="kr-display mt-1 text-3xl tabular-nums">{@value}</p>
      <p :if={@hint} class="mt-1 text-xs text-soft">{@hint}</p>
    </.link>
    """
  end
end
