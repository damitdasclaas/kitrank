defmodule KitrankWeb.SportsLiveTest do
  @moduledoc """
  Die Startseite ist die Sportart-Auswahl, die Übersicht hängt darunter.

  Geprüft wird beides: dass die Auswahl zeigt, was es gibt, und dass eine
  Sportart-Seite wirklich nur ihre eigenen Ligen zeigt — sonst wäre die
  Trennung nur Kosmetik in der Adresszeile.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  defp sportart(name, slug) do
    sport = sport_fixture(name: name, slug: slug)
    competition = competition_fixture(sport_id: sport.id, name: "#{name}-Liga", tier: 1)

    %{teams: teams, kits: kits} =
      league_fixture(
        competition: competition,
        season: Kits.current_season(),
        team_count: 2,
        kit_types: ["home"]
      )

    %{sport: sport, competition: competition, teams: teams, kits: kits}
  end

  describe "Sportart-Auswahl" do
    test "zeigt eine Kachel je Sportart mit Liga- und Vereinszahl", %{conn: conn} do
      sportart("Fußball", "fussball-auswahl")
      sportart("American Football", "nfl-auswahl")

      {:ok, _view, html} = live(conn, ~p"/")

      assert length(Regex.scan(~r/data-role="sport-card"/, html)) == 2
      assert html =~ "Fußball"
      assert html =~ "American Football"
      assert html =~ "1 Liga"
      assert html =~ "2 Vereine"
    end

    test "verlinkt auf die Übersicht der Sportart", %{conn: conn} do
      %{sport: sport} = sportart("Fußball", "fussball-link")
      ziel = "/" <> sport.slug

      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: ^ziel}}} =
               view |> element(~s{[data-role="sport-card"]}) |> render_click()
    end

    test "eine Sportart ohne Vereine in dieser Saison taucht nicht auf", %{conn: conn} do
      # Sonst wäre die Kachel ein Weg auf eine leere Seite.
      leer = sport_fixture(name: "Handball", slug: "handball-leer")
      competition_fixture(sport_id: leer.id, name: "Handball-Liga")
      sportart("Fußball", "fussball-nichtleer")

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Fußball"
      refute html =~ "Handball"
    end

    test "sagt es, wenn es noch gar nichts gibt", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Noch keine Trikots"
      refute html =~ ~s(data-role="sport-card")
    end
  end

  describe "Übersicht je Sportart" do
    setup do
      %{sport: fussball, teams: [f_team | _], kits: [f_kit | _]} =
        sportart("Fußball", "fussball-uebersicht")

      %{sport: nfl, teams: [n_team | _], kits: [n_kit | _]} =
        sportart("American Football", "nfl-uebersicht")

      %{fussball: fussball, nfl: nfl, f_team: f_team, n_team: n_team, f_kit: f_kit, n_kit: n_kit}
    end

    test "zeigt nur die Ligen dieser Sportart", %{conn: conn, fussball: fussball} do
      {:ok, _view, html} = live(conn, ~p"/#{fussball.slug}")

      assert html =~ "Fußball-Liga"
      refute html =~ "American Football-Liga"
    end

    test "und nur deren Vereine", %{conn: conn, fussball: fussball, f_team: f, n_team: n} do
      {:ok, _view, html} = live(conn, ~p"/#{fussball.slug}")

      assert html =~ f.name
      refute html =~ n.name
    end

    test "nennt die Sportart und führt zurück zur Auswahl", %{conn: conn, nfl: nfl} do
      {:ok, _view, html} = live(conn, ~p"/#{nfl.slug}")

      assert html =~ "American Football"
      assert html =~ "Sportarten"
      assert html =~ ~s(href="/")
    end

    test "ein Slug, den es nicht gibt, ist eine 404 und kein Absturz", %{conn: conn} do
      assert_raise KitrankWeb.NotFoundError, fn ->
        live(conn, "/gibtsnicht")
      end
    end
  end

  describe "Kategorien je Sportart" do
    setup do
      {:ok, nfl} =
        Kits.create_sport(%{
          name: "American Football",
          slug: "nfl-filter",
          kit_types: ["home", "away", "special"],
          special_label: "Alternate"
        })

      competition = competition_fixture(sport_id: nfl.id, name: "NFL")
      season = Kits.current_season()

      %{teams: [team]} =
        league_fixture(
          competition: competition,
          season: season,
          team_count: 1,
          kit_types: ["home", "away"]
        )

      %{nfl: nfl, team: team, season: season}
    end

    test "der Schalter bietet kein Ausweichtrikot an", %{conn: conn, nfl: nfl} do
      {:ok, _view, html} = live(conn, ~p"/#{nfl.slug}")

      assert html =~ ~s(phx-value-type="home" data-role="show-all-kits")
      assert html =~ ~s(phx-value-type="away" data-role="show-all-kits")
      refute html =~ ~s(phx-value-type="third")
    end

    test "und nennt Sondertrikots so, wie die Sportart sie nennt", %{
      conn: conn,
      nfl: nfl,
      team: team,
      season: season
    } do
      kit_fixture(team_id: team.id, season: season, kit_type: "special", name: "Throwback 1994")

      {:ok, _view, html} = live(conn, ~p"/#{nfl.slug}")

      assert html =~ "Alternate"
      refute html =~ "Sondertrikot"
    end

    test "im Fußball bleibt es bei der übersetzten Vorgabe", %{conn: conn} do
      %{sport: fussball, teams: [team]} = sportart_mit("Fußball", "fussball-filter", ["home"])
      kit_fixture(team_id: team.id, season: Kits.current_season(), kit_type: "special", name: "X")

      {:ok, _view, html} = live(conn, ~p"/#{fussball.slug}")

      assert html =~ "Sonder"
      refute html =~ "Alternate"
    end

    defp sportart_mit(name, slug, kit_types) do
      sport = sport_fixture(name: name, slug: slug)
      competition = competition_fixture(sport_id: sport.id, name: "#{name}-Liga")

      %{teams: teams} =
        league_fixture(
          competition: competition,
          season: Kits.current_season(),
          team_count: 1,
          kit_types: kit_types
        )

      %{sport: sport, teams: teams}
    end
  end

  describe "Der Vergleich reicht über Sportarten hinaus" do
    setup do
      %{sport: fussball, kits: [f_kit | _], teams: [f_team | _]} =
        sportart("Fußball", "fussball-vergleich")

      %{kits: [n_kit | _], teams: [n_team | _]} = sportart("American Football", "nfl-vergleich")

      %{fussball: fussball, f_kit: f_kit, n_kit: n_kit, f_team: f_team, n_team: n_team}
    end

    test "stellt ein Trikot der einen gegen eins der anderen", %{
      conn: conn,
      fussball: fussball,
      f_kit: f,
      n_kit: n,
      f_team: f_team,
      n_team: n_team
    } do
      # Der Grund, warum der Vergleich nicht unter der Sportart eingesperrt
      # ist: ein Bundesliga-Trikot gegen ein NFL-Trikot zu stellen kann diese
      # App, und trikotranking.de nicht.
      {:ok, _view, html} =
        live(conn, "/#{fussball.slug}/vergleich?trikots=#{f.id},#{n.id}")

      assert html =~ "Direktvergleich"
      assert html =~ f_team.name
      assert html =~ n_team.name
      assert html =~ "American Football-Liga"
    end

    test "das Raster darunter bleibt trotzdem bei seiner Sportart", %{
      conn: conn,
      fussball: fussball,
      f_kit: f,
      n_kit: n,
      n_team: n_team
    } do
      {:ok, view, _html} =
        live(conn, "/#{fussball.slug}/vergleich?trikots=#{f.id},#{n.id}")

      # Modal zu – im Raster steht der fremde Verein nicht.
      html = view |> element(~s{a[href="/#{fussball.slug}"]}) |> render_click()

      refute html =~ n_team.name
    end

    test "die Lupe zeigt auch ein Trikot aus der anderen Sportart", %{
      conn: conn,
      fussball: fussball,
      f_kit: f,
      n_kit: n
    } do
      # Die grosse Ansicht schlaegt im Raster nach — das kennt das fremde
      # Trikot nicht, also muss sie auch unter den verglichenen suchen.
      {:ok, n_kit} = Kits.update_kit(n, %{cutout_url: "https://example.com/nfl.jpg"})

      {:ok, view, _html} =
        live(conn, "/#{fussball.slug}/vergleich?trikots=#{f.id},#{n_kit.id}")

      html =
        view
        |> element(~s{[data-role="compare-zoom"][phx-value-id="#{n_kit.id}"]})
        |> render_click()

      assert html =~ ~s(id="kit-lightbox")
      assert html =~ "https://example.com/nfl.jpg"
    end
  end
end
