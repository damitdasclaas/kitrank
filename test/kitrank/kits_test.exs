defmodule Kitrank.KitsTest do
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures

  alias Kitrank.Kits

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

  describe "overview/1" do
    test "gruppiert nach Liga, sortiert nach tier und liefert Trikots in fachlicher Reihenfolge" do
      season = "2026/27"
      zweite = competition_fixture(name: "Zweite", tier: 2)
      erste = competition_fixture(name: "Erste", tier: 1)

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
      zweite = competition_fixture(name: "Zweite", tier: 2)
      erste = competition_fixture(name: "Erste", tier: 1)

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
