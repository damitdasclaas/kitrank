defmodule KitrankWeb.Admin.CrudTest do
  @moduledoc """
  Der Weg, den die Datenpflege wirklich nimmt: Liga anlegen, Verein anlegen,
  zuordnen, Trikot eintragen – und dann steht es in der Übersicht.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.AccountsFixtures
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  describe "Sportarten" do
    test "anlegen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sportarten/neu")

      view
      |> form("#sport-form", sport: %{name: "Fußball", slug: "football"})
      |> render_submit()

      assert [%{name: "Fußball", slug: "football"}] = Kits.list_sports()
    end

    test "zeigt Fehler statt zu speichern", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sportarten/neu")

      html =
        view
        |> form("#sport-form", sport: %{name: "", slug: "Groß Geschrieben"})
        |> render_submit()

      assert html =~ "darf nicht leer sein"
      assert Kits.list_sports() == []
    end
  end

  describe "Ligen" do
    test "anlegen mit Stufe", %{conn: conn} do
      sport = sport_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/ligen/neu")

      view
      |> form("#competition-form",
        competition: %{sport_id: sport.id, name: "Bundesliga", country: "DE", tier: 1}
      )
      |> render_submit()

      assert [%{name: "Bundesliga", tier: 1}] = Kits.list_competitions()
    end

    test "weist auf die fehlende Sportart hin, statt ein leeres Formular zu zeigen", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/ligen")
      assert html =~ "Erst braucht es eine"
    end
  end

  describe "Vereine" do
    test "anlegen, Kürzel wird großgeschrieben", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/vereine/neu")

      view
      |> form("#team-form",
        team: %{name: "FC Bayern München", short_code: "fcb", primary_color: "#DC052D"}
      )
      |> render_submit()

      assert [%{short_code: "FCB"}] = Kits.list_teams()
    end

    test "bearbeiten", %{conn: conn} do
      team = team_fixture(name: "Alter Name")
      {:ok, view, _html} = live(conn, ~p"/admin/vereine/#{team.id}")

      view
      |> form("#team-form", team: %{name: "Neuer Name"})
      |> render_submit()

      assert Kits.get_team!(team.id).name == "Neuer Name"
    end

    test "löschen", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/vereine")

      view |> element(~s{button[phx-click="delete"][phx-value-id="#{team.id}"]}) |> render_click()

      assert Kits.list_teams() == []
    end
  end

  describe "Saison-Zuordnung" do
    test "ordnet einen Verein einer Liga zu", %{conn: conn} do
      team = team_fixture()
      competition = competition_fixture()
      season = Kits.current_season()

      {:ok, view, _html} = live(conn, ~p"/admin/saison/neu")

      view
      |> form("#team_season-form",
        team_season: %{team_id: team.id, competition_id: competition.id, season: season}
      )
      |> render_submit()

      assert [row] = Kits.list_team_seasons(season)
      assert row.team_id == team.id
      assert row.competition_id == competition.id
    end

    test "lässt denselben Verein nicht zweimal in derselben Saison zu", %{conn: conn} do
      %{teams: [team], competition: competition, season: season} =
        league_fixture(team_count: 1, kit_types: [])

      other = competition_fixture(name: "Andere Liga", tier: 2)
      {:ok, view, _html} = live(conn, ~p"/admin/saison/neu")

      html =
        view
        |> form("#team_season-form",
          team_season: %{team_id: team.id, competition_id: other.id, season: season}
        )
        |> render_submit()

      assert html =~ "schon einer Liga zugeordnet"
      assert length(Kits.list_team_seasons(season)) == 1
      assert competition.id
    end
  end

  describe "Trikots" do
    setup do
      %{teams: [team], season: season} = league_fixture(team_count: 1, kit_types: [])
      %{team: team, season: season}
    end

    test "anlegen mit Bildern, eine URL pro Zeile", %{conn: conn, team: team, season: season} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots/neu")

      view
      |> form("#kit-form",
        kit: %{
          team_id: team.id,
          season: season,
          kit_type: "home",
          cutout_url: "https://example.com/cutout.png",
          model_image_urls: "https://example.com/a.jpg\nhttps://example.com/b.jpg",
          source_shop_url: "https://example.com/shop"
        }
      )
      |> render_submit()

      assert [kit] = Kits.list_kits(season)
      assert kit.cutout_url == "https://example.com/cutout.png"
      assert kit.model_image_urls == ["https://example.com/a.jpg", "https://example.com/b.jpg"]
    end

    test "legt mehrere Sondertrikots mit Namen an", %{conn: conn, team: team, season: season} do
      for name <- ["125 Jahre", "Weihnachten"] do
        {:ok, view, _html} = live(conn, ~p"/admin/trikots/neu")

        view
        |> form("#kit-form",
          kit: %{team_id: team.id, season: season, kit_type: "special", name: name}
        )
        |> render_submit()
      end

      sonder = Kits.list_kits(season) |> Enum.filter(&(&1.kit_type == "special"))
      assert length(sonder) == 2
      assert Enum.map(sonder, & &1.name) |> Enum.sort() == ["125 Jahre", "Weihnachten"]
    end

    test "verlangt bei Sondertrikots einen Namen", %{conn: conn, team: team, season: season} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots/neu")

      html =
        view
        |> form("#kit-form", kit: %{team_id: team.id, season: season, kit_type: "special"})
        |> render_submit()

      assert html =~ "brauchen einen Namen"
      assert Kits.list_kits(season) == []
    end

    test "zeigt den Namen in der Liste", %{conn: conn, team: team, season: season} do
      kit_fixture(team_id: team.id, season: season, kit_type: "special", name: "125 Jahre")

      {:ok, _view, html} = live(conn, ~p"/admin/trikots")

      assert html =~ "Sonder · 125 Jahre"
    end

    test "lehnt eine kaputte Bild-URL ab", %{conn: conn, team: team, season: season} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots/neu")

      html =
        view
        |> form("#kit-form",
          kit: %{
            team_id: team.id,
            season: season,
            kit_type: "home",
            model_image_urls: "https://example.com/a.jpg\nkeine-url"
          }
        )
        |> render_submit()

      assert html =~ "müssen mit http"
      assert Kits.list_kits(season) == []
    end

    test "ein angelegtes Trikot steht danach in der Übersicht", %{
      conn: conn,
      team: team,
      season: season
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots/neu")

      view
      |> form("#kit-form", kit: %{team_id: team.id, season: season, kit_type: "home"})
      |> render_submit()

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ team.name
    end
  end

  describe "Trikot-Liste filtern" do
    setup do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      season = Kits.current_season()

      %{teams: [a]} =
        league_fixture(competition: erste, season: season, team_count: 1, kit_types: ["home"])

      %{teams: [b]} =
        league_fixture(competition: zweite, season: season, team_count: 1, kit_types: ["home"])

      %{erste: erste, zweite: zweite, a: a, b: b}
    end

    test "zeigt ohne Filter alle Ligen", %{conn: conn, a: a, b: b} do
      {:ok, _view, html} = live(conn, ~p"/admin/trikots")

      assert html =~ a.name
      assert html =~ b.name
      assert html =~ "Erste Liga"
      assert html =~ "Zweite Liga"
      assert html =~ "2 Trikots"
    end

    test "grenzt auf eine Liga ein", %{conn: conn, erste: erste, a: a, b: b} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      html =
        view
        |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{erste.id}"]})
        |> render_click()

      assert html =~ a.name
      refute html =~ b.name
      assert html =~ "1 Trikots"
    end

    test "'Alle' hebt den Filter auf", %{conn: conn, erste: erste, b: b} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{erste.id}"]})
      |> render_click()

      html = view |> element(~s{button[phx-click="all_leagues"]}) |> render_click()

      assert html =~ b.name
    end

    test "sucht nach Vereinsnamen", %{conn: conn, a: a, b: b} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      html = view |> form("form[phx-change=\"search\"]", %{"q" => a.name}) |> render_change()

      assert html =~ a.name
      refute html =~ b.name
    end

    test "sucht auch nach dem Kürzel", %{conn: conn, a: a} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      html =
        view
        |> form("form[phx-change=\"search\"]", %{"q" => String.downcase(a.short_code)})
        |> render_change()

      assert html =~ a.name
    end

    test "kombiniert Suche und Liga-Filter", %{conn: conn, erste: erste, a: a, b: b} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{erste.id}"]})
      |> render_click()

      html = view |> form("form[phx-change=\"search\"]", %{"q" => b.name}) |> render_change()

      # b liegt in der anderen Liga – der Filter gewinnt, die Tabelle bleibt
      # leer. (b.name steht trotzdem im HTML: im Suchfeld.)
      assert html =~ "kein Trikot in dieser Auswahl"
      refute html =~ a.name
    end

    test "behandelt Prozentzeichen als Text, nicht als Muster", %{conn: conn, a: a} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      html = view |> form("form[phx-change=\"search\"]", %{"q" => "%"}) |> render_change()

      refute html =~ a.name
    end

    test "Suche und Liga-Filter überleben das Bearbeiten-Modal", %{
      conn: conn,
      erste: erste,
      a: a,
      b: b
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{erste.id}"]})
      |> render_click()

      view |> form("form[phx-change=\"search\"]", %{"q" => a.name}) |> render_change()

      # Aus der *gefilterten* Liste greifen – die ungefilterte kann mit einem
      # anderen Verein anfangen, dann steht der Link gar nicht auf der Seite.
      kit =
        Kits.list_kits_for_admin(Kits.current_season(),
          competition_ids: [erste.id],
          query: a.name
        )
        |> hd()
        |> Map.fetch!(:kit)

      # Modal auf ...
      html = view |> element(~s{a[href="/admin/trikots/#{kit.id}"]}) |> render_click()
      assert html =~ ~s(id="admin-form")

      # ... und wieder zu.
      html = view |> element(~s{#admin-form a}, "Abbrechen") |> render_click()

      refute html =~ ~s(id="admin-form")
      # Beides steht noch.
      assert html =~ ~s(value="#{a.name}")
      refute html =~ b.name
    end

    test "der Filter überlebt auch das Speichern", %{conn: conn, erste: erste, b: b} do
      {:ok, view, _html} = live(conn, ~p"/admin/trikots")

      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{erste.id}"]})
      |> render_click()

      kit = Kits.list_kits_for_admin(Kits.current_season(), competition_ids: [erste.id]) |> hd()
      view |> element(~s{a[href="/admin/trikots/#{kit.kit.id}"]}) |> render_click()

      html =
        view
        |> form("#kit-form", kit: %{cutout_url: "https://example.com/neu.jpg"})
        |> render_submit()

      refute html =~ ~s(id="admin-form")
      refute html =~ b.name
      assert Kits.get_kit!(kit.kit.id).cutout_url == "https://example.com/neu.jpg"
    end

    test "zeigt Trikots ohne Liga-Zuordnung, statt sie zu verstecken", %{conn: conn} do
      # Ein Verein ohne Saison-Zuordnung – in der Übersicht unsichtbar, im
      # Admin muss er auffallen.
      waise = team_fixture(name: "Verein ohne Liga")
      kit_fixture(team_id: waise.id, season: Kits.current_season(), kit_type: "home")

      {:ok, _view, html} = live(conn, ~p"/admin/trikots")

      assert html =~ "Verein ohne Liga"
      assert html =~ "keine Liga"
    end
  end

  describe "Dashboard" do
    test "zählt, was gepflegt ist, und was noch fehlt", %{conn: conn} do
      %{teams: [team], season: season} = league_fixture(team_count: 1, kit_types: [])
      kit_fixture(team_id: team.id, season: season, kit_type: "home")

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Was noch fehlt"
      assert html =~ "Trikots ohne Bild"
    end
  end
end
