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
       pruef_ergebnis: nil
     )}
  end

  @impl true
  def handle_event("bilder_pruefen", _params, socket) do
    {:noreply,
     socket
     |> assign(checking_images?: true, pruef_ergebnis: nil)
     |> start_async(:bilder_pruefen, fn -> Kitrank.Kits.ImageCheck.run() end)}
  end

  @impl true
  def handle_async(:bilder_pruefen, {:ok, auffaellig}, socket) do
    {:noreply, assign(socket, checking_images?: false, pruef_ergebnis: auffaellig)}
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

          <p :if={@pruef_ergebnis == []} class="mt-4 text-sm text-soft">
            Alle Adressen waren beim letzten Lauf erreichbar.
          </p>

          <div :if={@pruef_ergebnis not in [nil, []]} class="mt-4 space-y-5">
            <div :if={tot(@pruef_ergebnis) != []}>
              <h3 class="text-sm font-medium">{length(tot(@pruef_ergebnis))} wahrscheinlich tot</h3>
              <ul class="mt-2 space-y-2 text-sm">
                <li :for={eintrag <- tot(@pruef_ergebnis)} class="rounded border border-line p-2">
                  <p>
                    <span class="font-medium">{eintrag.kit.team.short_code}</span>
                    · {eintrag.feld} · {Kitrank.Kits.ProductImages.message(eintrag.grund)}
                  </p>
                  <p class="mt-1 break-all text-xs text-soft">{eintrag.url}</p>
                </li>
              </ul>
            </div>

            <div :if={unklar(@pruef_ergebnis) != []}>
              <h3 class="text-sm font-medium text-soft">
                {length(unklar(@pruef_ergebnis))} unklar – vermutlich nur Bot-Abwehr
              </h3>
              <p class="mt-1 text-xs text-soft">
                Die Prüfung läuft von diesem Server aus, nicht aus einem Browser. Manche Shops
                blocken Server-Adressen grundsätzlich – das heißt nicht, dass der Link für
                Besucher kaputt ist. Kein Grund zum Nachbessern, nur weil es hier steht.
              </p>
              <ul class="mt-2 space-y-2 text-sm">
                <li :for={eintrag <- unklar(@pruef_ergebnis)} class="rounded border border-line p-2">
                  <p>
                    <span class="font-medium">{eintrag.kit.team.short_code}</span>
                    · {eintrag.feld} · {Kitrank.Kits.ProductImages.message(eintrag.grund)}
                  </p>
                  <p class="mt-1 break-all text-xs text-soft">{eintrag.url}</p>
                </li>
              </ul>
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

  defp tot(ergebnis), do: Enum.filter(ergebnis, &(&1.kategorie == :tot))
  defp unklar(ergebnis), do: Enum.filter(ergebnis, &(&1.kategorie == :unklar))

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
