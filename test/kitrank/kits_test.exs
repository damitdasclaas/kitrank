defmodule Kitrank.KitsTest do
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Kits.Sport
  alias KitrankWeb.KitLabel

  describe "teams" do
    test "normalisiert das Kürzel auf Großbuchstaben" do
      {:ok, team} = Kits.create_team(%{name: "FC Bayern München", short_code: "fcb"})
      assert team.short_code == "FCB"
    end

    test "lehnt doppelte Kürzel ab" do
      team_fixture(short_code: "XYZ")
      assert {:error, changeset} = Kits.create_team(%{name: "Anderer", short_code: "XYZ"})
      assert "has already been taken" in errors_on(changeset).short_code
    end

    test "lehnt Farben ab, die keine Hex-Farbe sind" do
      assert {:error, changeset} =
               Kits.create_team(%{name: "X", short_code: "AAA", primary_color: "rot"})

      assert changeset.errors[:primary_color]
    end

    test "nimmt auch einen sehr langen Shop-Link" do
      lang = "https://example.com/shop?context=" <> String.duplicate("y", 400)

      assert {:ok, team} =
               Kits.create_team(%{name: "Langlink", short_code: "LNG", shop_url: lang})

      assert String.length(team.shop_url) > 255
    end

    test "lehnt Shop-URLs ab, die kein http(s) sind" do
      assert {:error, changeset} =
               Kits.create_team(%{
                 name: "X",
                 short_code: "AAB",
                 shop_url: "javascript:alert(1)"
               })

      assert changeset.errors[:shop_url]
    end
  end

  describe "team_seasons" do
    test "erlaubt demselben Team unterschiedliche Ligen in unterschiedlichen Saisons" do
      team = team_fixture()
      liga1 = competition_fixture(tier: 1)
      liga2 = competition_fixture(tier: 2)

      assert {:ok, _} =
               Kits.create_team_season(%{
                 team_id: team.id,
                 competition_id: liga1.id,
                 season: "2025/26"
               })

      assert {:ok, _} =
               Kits.create_team_season(%{
                 team_id: team.id,
                 competition_id: liga2.id,
                 season: "2026/27"
               })
    end

    test "lässt ein Team pro Saison nur in einer Liga spielen" do
      team = team_fixture()
      liga1 = competition_fixture(tier: 1)
      liga2 = competition_fixture(tier: 2)

      {:ok, _} =
        Kits.create_team_season(%{team_id: team.id, competition_id: liga1.id, season: "2026/27"})

      assert {:error, changeset} =
               Kits.create_team_season(%{
                 team_id: team.id,
                 competition_id: liga2.id,
                 season: "2026/27"
               })

      assert changeset.errors[:team_id]
    end

    test "lehnt kaputte Saison-Formate ab" do
      team = team_fixture()
      competition = competition_fixture()

      assert {:error, changeset} =
               Kits.create_team_season(%{
                 team_id: team.id,
                 competition_id: competition.id,
                 season: "2026"
               })

      assert changeset.errors[:season]
    end
  end

  describe "kits" do
    test "erlaubt pro Team und Saison jeden Kit-Typ nur einmal" do
      team = team_fixture()
      kit_fixture(team_id: team.id, kit_type: "home")

      assert {:error, changeset} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: Kits.current_season(),
                 kit_type: "home"
               })

      assert changeset.errors[:team_id]
    end

    test "erlaubt beliebig viele Sondertrikots pro Saison" do
      team = team_fixture()

      for name <- ["125 Jahre", "Weihnachten", "Stadtmeister"] do
        assert {:ok, _} =
                 Kits.create_kit(%{
                   team_id: team.id,
                   season: Kits.current_season(),
                   kit_type: "special",
                   name: name
                 })
      end

      sonder = Kits.list_kits() |> Enum.filter(&(&1.kit_type == "special"))
      assert length(sonder) == 3
    end

    test "verlangt bei Sondertrikots einen Namen" do
      team = team_fixture()

      assert {:error, changeset} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: Kits.current_season(),
                 kit_type: "special"
               })

      assert "Sondertrikots brauchen einen Namen, um sie zu unterscheiden" in errors_on(changeset).name
    end

    test "lehnt zwei Sondertrikots mit demselben Namen ab" do
      team = team_fixture()

      attrs = %{
        team_id: team.id,
        season: Kits.current_season(),
        kit_type: "special",
        name: "Derby"
      }

      assert {:ok, _} = Kits.create_kit(attrs)
      assert {:error, changeset} = Kits.create_kit(attrs)
      assert changeset.errors[:team_id]
    end

    test "Heim, Auswärts und Ausweich bleiben auf eines begrenzt" do
      team = team_fixture()

      for kit_type <- ~w(home away third) do
        attrs = %{team_id: team.id, season: Kits.current_season(), kit_type: kit_type}
        assert {:ok, _} = Kits.create_kit(attrs)
        assert {:error, changeset} = Kits.create_kit(attrs)
        assert changeset.errors[:team_id]
      end
    end

    test "ein Name ausserhalb von Sondertrikots ist erlaubt, aber nicht nötig" do
      team = team_fixture()

      assert {:ok, ohne} =
               Kits.create_kit(%{team_id: team.id, season: "2025/26", kit_type: "home"})

      assert ohne.name == nil

      assert {:ok, mit} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: "2026/27",
                 kit_type: "home",
                 name: "Retro"
               })

      assert KitrankWeb.KitLabel.display(mit) == "Heim · Retro"
      assert KitrankWeb.KitLabel.display(ohne) == "Heim"
    end

    test "lehnt unbekannte Kit-Typen ab" do
      team = team_fixture()

      assert {:error, changeset} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: Kits.current_season(),
                 kit_type: "goalkeeper_special_edition"
               })

      assert changeset.errors[:kit_type]
    end

    test "nimmt auch sehr lange URLs" do
      # Die TSG haengt einen base64-kodierten Kontext an ihre Bildadressen –
      # 352 Zeichen. Als varchar(255) gab das einen rohen Postgres-Fehler, der
      # die LiveView mitgenommen hat.
      lang = "https://example.com/bild.png?context=" <> String.duplicate("x", 400)
      team = team_fixture()

      assert {:ok, kit} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: Kits.current_season(),
                 kit_type: "home",
                 cutout_url: lang,
                 model_image_urls: [lang],
                 source_shop_url: lang
               })

      assert String.length(kit.cutout_url) > 255
      assert [gespeichert] = kit.model_image_urls
      assert String.length(gespeichert) > 255
    end

    test "prüft jede einzelne Bild-URL" do
      team = team_fixture()

      assert {:error, changeset} =
               Kits.create_kit(%{
                 team_id: team.id,
                 season: Kits.current_season(),
                 kit_type: "away",
                 model_image_urls: ["https://example.com/ok.jpg", "nicht-mal-eine-url"]
               })

      assert changeset.errors[:model_image_urls]
    end
  end

  describe "Trikot-Kategorien je Sportart" do
    test "eine neue Sportart kennt alle Kategorien" do
      # Der bisherige globale Satz als Vorgabe: bestehende Daten verhalten sich
      # nach der Migration wie vorher.
      {:ok, sport} = Kits.create_sport(%{name: "Handball", slug: "handball-vorgabe"})

      assert sport.kit_types == ~w(home away third special)
    end

    test "die NFL kennt kein Ausweichtrikot" do
      {:ok, sport} =
        Kits.create_sport(%{
          name: "American Football",
          slug: "nfl-kategorien",
          kit_types: ["home", "away", "special"]
        })

      assert Sport.kit_types(sport) == ["home", "away", "special"]
      refute "third" in Sport.kit_types(sport)
    end

    test "leere Datensaetze legt der Import nur fuer die einmaligen an" do
      # Von Heim/Auswaerts/Ausweich gibt es genau eins je Verein und Saison.
      # Ein Sondertrikot braucht einen Namen – ein leeres, namenloses gaebe es
      # gar nicht.
      {:ok, sport} =
        Kits.create_sport(%{
          name: "American Football",
          slug: "nfl-einzeln",
          kit_types: ["home", "away", "special"]
        })

      assert Sport.einzelne_kit_types(sport) == ["home", "away"]
    end

    test "eine erfundene Kategorie wird abgelehnt" do
      assert {:error, changeset} =
               Kits.create_sport(%{name: "X", slug: "x-erfunden", kit_types: ["throwback"]})

      assert %{kit_types: _} = errors_on(changeset)
    end

    test "ohne Kategorie geht es nicht" do
      assert {:error, changeset} =
               Kits.create_sport(%{name: "X", slug: "x-leer", kit_types: []})

      assert %{kit_types: _} = errors_on(changeset)
    end

    test "Sondertrikots koennen je Sportart anders heissen" do
      {:ok, nfl} =
        Kits.create_sport(%{
          name: "American Football",
          slug: "nfl-beschriftung",
          kit_types: ["home", "away", "special"],
          special_label: "Alternate"
        })

      {:ok, fussball} = Kits.create_sport(%{name: "Fußball", slug: "fussball-beschriftung"})

      assert KitLabel.label(nfl, "special") == "Alternate"
      # Ohne eigene Angabe bleibt es bei der uebersetzten Vorgabe.
      assert KitLabel.label(fussball, "special") == KitLabel.label("special")
      # Alles andere heisst ueberall gleich.
      assert KitLabel.label(nfl, "home") == KitLabel.label("home")
    end
  end

  describe "Trikots ohne Kategorie in ihrer Sportart" do
    setup do
      {:ok, sport} =
        Kits.create_sport(%{
          name: "American Football",
          slug: "nfl-verwaist",
          kit_types: ["home", "away", "special"]
        })

      competition = competition_fixture(sport_id: sport.id, name: "NFL")
      season = Kits.current_season()

      %{teams: [team]} =
        league_fixture(competition: competition, season: season, team_count: 1, kit_types: [])

      %{sport: sport, team: team, season: season}
    end

    test "findet ein leeres Trikot einer abgelegten Kategorie", %{team: team, season: season} do
      kit_fixture(team_id: team.id, season: season, kit_type: "third")

      assert %{loeschbar: [eintrag], belegt: []} = Kits.orphan_kits(season)
      assert eintrag.kit.kit_type == "third"
    end

    test "eine Kategorie, die die Sportart kennt, bleibt unangetastet", %{
      team: team,
      season: season
    } do
      kit_fixture(team_id: team.id, season: season, kit_type: "home")

      assert %{loeschbar: [], belegt: []} = Kits.orphan_kits(season)
    end

    test "ein Trikot mit Bild wird gemeldet, nicht geloescht", %{team: team, season: season} do
      kit_fixture(
        team_id: team.id,
        season: season,
        kit_type: "third",
        cutout_url: "https://example.com/x.jpg"
      )

      assert %{loeschbar: [], belegt: [_]} = Kits.orphan_kits(season)
      assert %{geloescht: 0} = Kits.remove_orphan_kits(season)
    end

    test "ein Trikot in einer Rangliste wird gemeldet, nicht geloescht", %{
      team: team,
      season: season
    } do
      # Der Fremdschluessel steht auf delete_all – loeschen wuerde es still aus
      # fremden Ranglisten entfernen.
      kit = kit_fixture(team_id: team.id, season: season, kit_type: "third")
      {:ok, ranking} = Kitrank.Rankings.create_ranking(%{display_name: "Test"})
      {:ok, _} = Kitrank.Rankings.add_kit(ranking, kit.id)

      assert %{loeschbar: [], belegt: [eintrag]} = Kits.orphan_kits(season)
      assert eintrag.eintraege == 1

      assert %{geloescht: 0} = Kits.remove_orphan_kits(season)
      assert Kits.get_kit!(kit.id)
    end

    test "loescht, was wirklich niemand braucht", %{team: team, season: season} do
      kit = kit_fixture(team_id: team.id, season: season, kit_type: "third")

      assert %{geloescht: 1} = Kits.remove_orphan_kits(season)
      assert_raise Ecto.NoResultsError, fn -> Kits.get_kit!(kit.id) end
    end
  end

  describe "Sportart-Slugs" do
    test "ein Slug, der schon ein Pfad ist, wird abgelehnt" do
      # /:sport steht ganz unten im Router und faengt alles ab, was davor nicht
      # gepasst hat. Eine Sportart namens "reveal" waere unerreichbar, und
      # niemand saehe warum.
      for slug <- Kitrank.Kits.Sport.reservierte_slugs() do
        assert {:error, changeset} = Kits.create_sport(%{name: "Test", slug: slug})
        assert %{slug: [msg]} = errors_on(changeset)
        assert msg =~ "Pfad der Anwendung"
      end
    end

    test "ein freier Slug geht durch" do
      assert {:ok, %{slug: "basketball"}} =
               Kits.create_sport(%{name: "Basketball", slug: "basketball"})
    end
  end

  describe "overview/1" do
    test "gruppiert nach Liga, sortiert nach tier und liefert Trikots in fachlicher Reihenfolge" do
      season = "2026/27"
      # Dieselbe Sportart, sonst entscheidet die und nicht die Spielklasse –
      # competition_fixture legt sonst je Liga eine eigene an.
      sport = sport_fixture()
      zweite = competition_fixture(sport_id: sport.id, name: "Zweite", tier: 2)
      erste = competition_fixture(sport_id: sport.id, name: "Erste", tier: 1)

      league_fixture(competition: zweite, season: season, team_count: 1, kit_types: ["home"])

      league_fixture(
        competition: erste,
        season: season,
        team_count: 2,
        kit_types: ["special", "away", "home"]
      )

      assert [{first, first_teams}, {second, _}] = Kits.overview(season)
      assert first.tier == 1
      assert second.tier == 2
      assert length(first_teams) == 2

      # Sortierung nicht alphabetisch ("away" käme sonst vor "home").
      {_team, kits} = hd(first_teams)
      assert Enum.map(kits, & &1.kit_type) == ["home", "away", "special"]
    end

    test "sortiert nach Sportart, dann Land, dann Spielklasse" do
      # Der Fall, um den es geht: die NFL ist erste Liga, schob sich damit
      # aber zwischen 1. und 2. Bundesliga. Ligen eines Landes gehoeren
      # beieinander.
      season = "2026/27"
      fussball = sport_fixture(name: "Fußball", slug: "fussball-sortierung")
      football = sport_fixture(name: "American Football", slug: "nfl-sortierung")

      bl2 =
        competition_fixture(sport_id: fussball.id, name: "2. Bundesliga", country: "DE", tier: 2)

      nfl = competition_fixture(sport_id: football.id, name: "NFL", country: "US", tier: 1)
      bl1 = competition_fixture(sport_id: fussball.id, name: "Bundesliga", country: "DE", tier: 1)

      for competition <- [bl2, nfl, bl1] do
        league_fixture(
          competition: competition,
          season: season,
          team_count: 1,
          kit_types: ["home"]
        )
      end

      namen = Kits.overview(season) |> Enum.map(fn {c, _} -> c.name end)

      assert namen == ["Bundesliga", "2. Bundesliga", "NFL"]
    end

    test "zeigt nur die angefragte Saison" do
      league_fixture(season: "2025/26", team_count: 1)
      league_fixture(season: "2026/27", team_count: 3)

      assert [{_competition, teams}] = Kits.overview("2026/27")
      assert length(teams) == 3
    end

    test "ist leer, wenn für die Saison keine Zuordnungen existieren" do
      assert Kits.overview("2099/00") == []
    end

    test "lässt Teams ohne Trikots nicht verschwinden" do
      %{competition: competition, season: season} =
        league_fixture(team_count: 1, kit_types: [])

      assert [{^competition, [{_team, []}]}] = Kits.overview(season)
    end
  end

  describe "list_rankable_kits/1" do
    test "liefert alle Trikots der Saison flach in Übersichts-Reihenfolge" do
      season = "2026/27"
      sport = sport_fixture()
      zweite = competition_fixture(sport_id: sport.id, name: "Zweite", tier: 2)
      erste = competition_fixture(sport_id: sport.id, name: "Erste", tier: 1)

      league_fixture(competition: zweite, season: season, team_count: 1, kit_types: ["home"])

      league_fixture(
        competition: erste,
        season: season,
        team_count: 1,
        kit_types: ["away", "home"]
      )

      kits = Kits.list_rankable_kits(season)

      assert length(kits) == 3
      # Erstliga-Team zuerst, dort home vor away.
      assert Enum.map(kits, & &1.kit_type) == ["home", "away", "home"]
      assert Enum.all?(kits, &Ecto.assoc_loaded?(&1.team))
    end

    test "ignoriert Trikots ohne Liga-Zuordnung in dieser Saison" do
      kit_fixture(season: "2026/27")
      assert Kits.list_rankable_kits("2026/27") == []
    end
  end

  describe "get_team_with_kits!/2" do
    test "lädt nur die Trikots der angefragten Saison" do
      team = team_fixture()
      kit_fixture(team_id: team.id, season: "2025/26", kit_type: "home")
      kit_fixture(team_id: team.id, season: "2026/27", kit_type: "home")
      kit_fixture(team_id: team.id, season: "2026/27", kit_type: "away")

      loaded = Kits.get_team_with_kits!(team.id, "2026/27")
      assert Enum.map(loaded.kits, & &1.kit_type) == ["home", "away"]
    end
  end
end
