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
       without_shop: Enum.count(kits, &(&1.source_shop_url in [nil, ""]))
     )}
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
