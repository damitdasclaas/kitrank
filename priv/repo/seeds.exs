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
  {"HSV", "Hamburger SV", "#005CA9", bundesliga},
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

# ── Ein Verein mit echten Daten ───────────────────────────────────────────────
# Der Rest oben ist Platzhalter ohne Bilder. Der HSV ist vollständig gepflegt,
# damit sich beides nebeneinander ansehen lässt: echte Shop-Bilder gegen die
# gezeichneten Silhouetten.
#
# Die Bild-URLs zeigen direkt auf das CDN des HSV-Shops – KitRank hostet keine
# Trikotbilder (Architektur Abschnitt 5). Bricht ein Link, fällt die Übersicht
# von allein auf die gezeichnete Darstellung zurück.

hsv = Repo.get_by!(Team, short_code: "HSV")

hsv = Ecto.Changeset.change(hsv, shop_url: "https://shop.hsv.de") |> Repo.update!()

hsv_kits = [
  %{
    kit_type: "home",
    cutout_url:
      "https://4a2e5bfda6.edge.storage/res/product_450/adidas-Heimtrikot-2627---0b5325e3-125a-4158-8353-7180c1a357b4.jpg",
    model_image_urls: [
      "https://4a2e5bfda6.edge.storage/res/viewone_450/adidas-Heimtrikot-2627---b7bb3641-c258-4bb7-bfdc-8c292cf14ab5.jpg",
      "https://4a2e5bfda6.edge.storage/res/viewthree_450/adidas-Heimtrikot-2627---a05e196e-68aa-4ad2-93dc-1a758c319735.jpg"
    ],
    source_shop_url:
      "https://shop.hsv.de/adidas-Heimtrikot-2627/products/14284?categoryId=2&locale=de"
  },
  %{
    kit_type: "away",
    cutout_url:
      "https://4a2e5bfda6.edge.storage/res/product_450/adidas-Ausw%C3%A4rtstrikot-2627---e1944d88-ef53-452e-b346-40e18f3fc11b.jpg",
    model_image_urls: [
      "https://4a2e5bfda6.edge.storage/res/viewfive_450/adidas-Ausw%C3%A4rtstrikot-2627---c71b1084-d6a6-4c96-99b6-b14cb682908e.jpg",
      "https://4a2e5bfda6.edge.storage/res/viewtwo_450/adidas-Ausw%C3%A4rtstrikot-2627---1a54d48c-d149-41c1-aba2-1bb95232f839.jpg"
    ],
    source_shop_url:
      "https://shop.hsv.de/adidas-Ausw%C3%A4rtstrikot-2627/products/14350?categoryId=2&locale=de"
  },
  %{
    kit_type: "third",
    cutout_url:
      "https://4a2e5bfda6.edge.storage/res/product_450/adidas-Ausweichtrikot-2627---62110a2d-0a47-4091-b9a8-555fb3e0bcd9.jpg",
    model_image_urls: [
      "https://4a2e5bfda6.edge.storage/res/viewone_450/adidas-Ausweichtrikot-2627---d8629c9a-4c81-402c-8e5b-b543347cbc05.jpg",
      "https://4a2e5bfda6.edge.storage/res/viewtwo_450/adidas-Ausweichtrikot-2627---f7f0500b-f9d9-4b70-bded-e38904eeff22.jpg"
    ],
    source_shop_url:
      "https://shop.hsv.de/adidas-Ausweichtrikot-2627/products/14436?categoryId=2&locale=de"
  }
]

for attrs <- hsv_kits do
  upsert.(
    Kit,
    [team_id: hsv.id, season: season, kit_type: attrs.kit_type],
    Map.merge(attrs, %{team_id: hsv.id, season: season})
  )
end

IO.puts("""
Seeds fertig für Saison #{season}:
  #{length(Kits.list_teams())} Teams
  #{length(Kits.list_competitions())} Wettbewerbe
  #{length(Kits.list_kits(season))} Trikots

Bis auf den HSV sind Bild- und Shop-URLs absichtlich leer – die pflegst du
über /admin. Der HSV zeigt, wie es mit echten Bildern aussieht.
""")
