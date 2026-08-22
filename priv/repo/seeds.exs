# Dev-Seeds: befüllt eine lokale Datenbank schnell mit einem realistischen Stand.
#
# Die Stammdaten kommen aus derselben Datei, die auch in Produktion eingespielt
# wird (priv/data/teams_2026_27.json) – es gibt keine zweite, erfundene Liste,
# die auseinanderlaufen könnte.
#
# Ergänzt werden hier nur Trikots, denn die gehören nicht in die Import-Datei:
#   * für alle Vereine leere Trikots, damit die Übersicht die gezeichnete
#     Darstellung zeigt
#   * für den HSV echte Bilder aus dem Vereinsshop, damit beides nebeneinander
#     zu sehen ist
#
#     mix run priv/repo/seeds.exs
#
# Idempotent – mehrfaches Ausführen legt nichts doppelt an.

alias Kitrank.Repo
alias Kitrank.Kits
alias Kitrank.Kits.{Kit, Season, Team}

{:ok, bericht} = Kits.Import.run()
IO.puts(Kits.Import.format(bericht))

season = Season.current()

upsert = fn schema, keys, attrs ->
  case Repo.get_by(schema, keys) do
    nil -> schema |> struct() |> schema.changeset(attrs) |> Repo.insert!()
    existing -> existing |> schema.changeset(attrs) |> Repo.update!()
  end
end

# Heim/Auswärts/Ausweich für alle – ohne Bilder, die zeichnet die Übersicht.
for team <- Kits.list_teams(), kit_type <- ~w(home away third) do
  upsert.(Kit, [team_id: team.id, season: season, kit_type: kit_type], %{
    team_id: team.id,
    season: season,
    kit_type: kit_type
  })
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
  #{length(Kits.list_teams())} Vereine
  #{length(Kits.list_kits(season))} Trikots

Bis auf den HSV sind Bild- und Shop-URLs leer – die pflegst du über /admin.
Der HSV zeigt, wie es mit echten Bildern aussieht.
""")
