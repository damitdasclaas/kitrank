defmodule Kitrank.Kits.ImportTest do
  @moduledoc """
  Der Import ist der Weg, wie Stammdaten in Produktion landen — und wie sie
  jedes Jahr aktualisiert werden. Beides wird hier geprüft.
  """
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Kits.Import

  @tmp System.tmp_dir!()

  defp datei(data) do
    pfad = Path.join(@tmp, "import-#{System.unique_integer([:positive])}.json")
    File.write!(pfad, JSON.encode!(data))
    on_exit(fn -> File.rm(pfad) end)
    pfad
  end

  defp saison_daten(season, bl1, bl2 \\ []) do
    %{
      "season" => season,
      "sport" => %{"name" => "Fußball", "slug" => "football"},
      "competitions" => [
        %{"name" => "Bundesliga", "country" => "DE", "tier" => 1, "teams" => bl1},
        %{"name" => "2. Bundesliga", "country" => "DE", "tier" => 2, "teams" => bl2}
      ]
    }
  end

  defp verein(name, code, farbe \\ "#DC052D") do
    %{"name" => name, "short_code" => code, "primary_color" => farbe, "shop_url" => nil}
  end

  describe "Ersteinspielung" do
    test "legt Sportart, Ligen, Vereine und Zuordnungen an" do
      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")], [verein("HSV", "HSV")]))

      assert {:ok, bericht} = Import.run(pfad)

      assert bericht.ligen == 2
      assert bericht.teams.neu == 2
      assert bericht.zuordnungen.neu == 2

      assert [%{slug: "football"}] = Kits.list_sports()
      assert length(Kits.list_competitions()) == 2
      assert [{erste, [{team, _}]}, {_zweite, _}] = Kits.overview("2026/27")
      assert erste.name == "Bundesliga"
      assert team.short_code == "FCB"
    end

    test "normalisiert das Kürzel" do
      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "fcb")]))
      {:ok, _} = Import.run(pfad)

      assert [%{short_code: "FCB"}] = Kits.list_teams()
    end
  end

  describe "Wiederholtes Einspielen" do
    setup do
      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")], [verein("HSV", "HSV")]))
      {:ok, _} = Import.run(pfad)
      %{pfad: pfad}
    end

    test "ändert beim zweiten Lauf nichts", %{pfad: pfad} do
      assert {:ok, bericht} = Import.run(pfad)

      assert bericht.teams == %{neu: 0, geaendert: 0, unveraendert: 2}
      assert bericht.zuordnungen == %{neu: 0, geaendert: 0, unveraendert: 2}
      assert length(Kits.list_teams()) == 2
      assert length(Kits.list_competitions()) == 2
    end

    test "übernimmt eine geänderte Vereinsfarbe" do
      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB", "#ED0038")]))
      {:ok, bericht} = Import.run(pfad)

      assert bericht.teams.geaendert == 1
      assert Enum.find(Kits.list_teams(), &(&1.short_code == "FCB")).primary_color == "#ED0038"
    end

    test "löscht keinen im Admin gepflegten Shop-Link" do
      team = Enum.find(Kits.list_teams(), &(&1.short_code == "FCB"))
      {:ok, _} = Kits.update_team(team, %{shop_url: "https://fcbayern.com/shop"})

      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")]))
      {:ok, _} = Import.run(pfad)

      assert Kits.get_team!(team.id).shop_url == "https://fcbayern.com/shop"
    end
  end

  describe "Auf- und Abstieg" do
    setup do
      pfad =
        datei(
          saison_daten(
            "2026/27",
            [verein("FC Bayern", "FCB"), verein("FC St. Pauli", "STP")],
            [verein("HSV", "HSV")]
          )
        )

      {:ok, _} = Import.run(pfad)
      :ok
    end

    test "verschiebt einen Verein in die andere Liga" do
      # HSV steigt auf, St. Pauli ab.
      pfad =
        datei(
          saison_daten(
            "2026/27",
            [verein("FC Bayern", "FCB"), verein("HSV", "HSV")],
            [verein("FC St. Pauli", "STP")]
          )
        )

      assert {:ok, bericht} = Import.run(pfad)
      assert bericht.zuordnungen.geaendert == 2

      [{erste, erste_teams}, {_zweite, zweite_teams}] = Kits.overview("2026/27")
      assert erste.tier == 1
      assert Enum.map(erste_teams, fn {t, _} -> t.short_code end) |> Enum.sort() == ["FCB", "HSV"]
      assert Enum.map(zweite_teams, fn {t, _} -> t.short_code end) == ["STP"]
    end

    test "entfernt Zuordnungen, die nicht mehr in der Datei stehen" do
      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")]))

      assert {:ok, bericht} = Import.run(pfad)
      assert bericht.entfernt == 2

      assert [{_erste, [{team, _}]}] = Kits.overview("2026/27")
      assert team.short_code == "FCB"
    end

    test "lässt die Vereine selbst und ihre Trikots stehen" do
      hsv = Enum.find(Kits.list_teams(), &(&1.short_code == "HSV"))
      kit_fixture(team_id: hsv.id, season: "2026/27", kit_type: "home")

      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")]))
      {:ok, _} = Import.run(pfad)

      # Aus der Übersicht raus, aber nicht aus der Datenbank – sonst wären mit
      # dem Abstieg auch alle Trikots früherer Saisons weg.
      assert Kits.get_team!(hsv.id)
      assert Kits.list_kits("2026/27") |> Enum.any?(&(&1.team_id == hsv.id))
    end

    test "rührt andere Saisons nicht an" do
      hsv = Enum.find(Kits.list_teams(), &(&1.short_code == "HSV"))
      andere = competition_fixture(name: "Alte Liga", tier: 1)

      {:ok, _} =
        Kits.create_team_season(%{
          team_id: hsv.id,
          competition_id: andere.id,
          season: "2025/26"
        })

      pfad = datei(saison_daten("2026/27", [verein("FC Bayern", "FCB")]))
      {:ok, _} = Import.run(pfad)

      assert length(Kits.list_team_seasons("2025/26")) == 1
    end
  end

  describe "Kaputte Eingaben" do
    test "meldet eine fehlende Datei" do
      assert {:error, meldung} = Import.run("/gibt/es/nicht.json")
      assert meldung =~ "nicht gefunden"
    end

    test "meldet ungültiges JSON" do
      pfad = Path.join(@tmp, "kaputt-#{System.unique_integer([:positive])}.json")
      File.write!(pfad, "{kein json")
      on_exit(fn -> File.rm(pfad) end)

      assert {:error, meldung} = Import.run(pfad)
      assert meldung =~ "JSON"
    end

    test "meldet fehlende Schlüssel" do
      pfad = datei(%{"season" => "2026/27"})
      assert {:error, meldung} = Import.run(pfad)
      assert meldung =~ "season, sport und competitions"
    end

    test "bricht bei einer ungültigen Farbe komplett ab, statt halb zu importieren" do
      pfad =
        datei(
          saison_daten("2026/27", [
            verein("FC Bayern", "FCB"),
            verein("Kaputt", "XXX", "rot")
          ])
        )

      assert {:error, meldung} = Import.run(pfad)
      assert meldung =~ "primary_color"
      # Nichts davon darf stehenbleiben.
      assert Kits.list_teams() == []
      assert Kits.list_sports() == []
    end
  end

  describe "Die mitgelieferte Datei" do
    test "lässt sich einspielen und ergibt 18 + 18" do
      assert {:ok, bericht} = Import.run()

      assert bericht.season == "2026/27"
      assert bericht.teams.neu == 36

      assert [{erste, erste_teams}, {zweite, zweite_teams}] = Kits.overview("2026/27")
      assert erste.name == "Bundesliga"
      assert erste.tier == 1
      assert length(erste_teams) == 18
      assert zweite.name == "2. Bundesliga"
      assert length(zweite_teams) == 18
    end
  end
end
