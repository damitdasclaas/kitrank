# Dev-Seeds: befüllt eine lokale Datenbank schnell mit einer plausiblen Struktur.
#
# Bewusst KEINE Dauerlösung für die Datenpflege – dafür ist die Admin-UI da
# (Architektur Abschnitt 4.4). Entsprechend stehen hier nur ein paar Beispiel-
# Teams, nicht die vollständigen Ligen, und die Bild-/Shop-URLs sind leer:
# echte Trikotbilder werden verlinkt, nicht gehostet (Abschnitt 5), und die
# konkreten Deep-Links trägst du im Admin ein.
#
#     mix run priv/repo/seeds.exs
#
# Das Skript ist idempotent – mehrfaches Ausführen legt nichts doppelt an.

alias Kitrank.Repo
alias Kitrank.Kits
alias Kitrank.Kits.{Competition, Kit, Season, Sport, Team, TeamSeason}

season = Season.current()

upsert = fn schema, keys, attrs ->
  case Repo.get_by(schema, keys) do
    nil ->
      schema
      |> struct()
      |> schema.changeset(attrs)
      |> Repo.insert!()

    existing ->
      existing
      |> schema.changeset(attrs)
      |> Repo.update!()
  end
end

football = upsert.(Sport, [slug: "football"], %{name: "Fußball", slug: "football"})

bundesliga =
  upsert.(Competition, [sport_id: football.id, country: "DE", name: "Bundesliga"], %{
    sport_id: football.id,
    name: "Bundesliga",
    country: "DE",
    tier: 1
  })

bundesliga_2 =
  upsert.(Competition, [sport_id: football.id, country: "DE", name: "2. Bundesliga"], %{
    sport_id: football.id,
    name: "2. Bundesliga",
    country: "DE",
    tier: 2
  })

# {Kürzel, Name, Vereinsfarbe, Liga} – Beispielauswahl, keine vollständige Saison.
teams = [
  {"FCB", "FC Bayern München", "#DC052D", bundesliga},
  {"BVB", "Borussia Dortmund", "#FDE100", bundesliga},
  {"SGE", "Eintracht Frankfurt", "#E1000F", bundesliga},
  {"BMG", "Borussia Mönchengladbach", "#000000", bundesliga},
  {"SVW", "SV Werder Bremen", "#1D9053", bundesliga},
  {"FCSP", "FC St. Pauli", "#6B4423", bundesliga},
  {"HSV", "Hamburger SV", "#005CA9", bundesliga_2},
  {"S04", "FC Schalke 04", "#004D9D", bundesliga_2},
  {"H96", "Hannover 96", "#00963F", bundesliga_2},
  {"KSC", "Karlsruher SC", "#005CA9", bundesliga_2}
]

for {short_code, name, color, competition} <- teams do
  team =
    upsert.(Team, [short_code: short_code], %{
      name: name,
      short_code: short_code,
      primary_color: color
    })

  upsert.(TeamSeason, [team_id: team.id, season: season], %{
    team_id: team.id,
    competition_id: competition.id,
    season: season
  })

  # Heim/Auswärts/Ausweich pro Team – Bild- und Shop-URLs kommen aus dem Admin.
  for kit_type <- ~w(home away third) do
    upsert.(Kit, [team_id: team.id, season: season, kit_type: kit_type], %{
      team_id: team.id,
      season: season,
      kit_type: kit_type
    })
  end
end

IO.puts("""
Seeds fertig für Saison #{season}:
  #{length(Kits.list_teams())} Teams
  #{length(Kits.list_competitions())} Wettbewerbe
  #{length(Kits.list_kits(season))} Trikots

Bild- und Shop-URLs sind absichtlich leer – die pflegst du über /admin.
""")
