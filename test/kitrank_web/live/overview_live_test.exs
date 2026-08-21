defmodule KitrankWeb.OverviewLiveTest do
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  # Alle Tests laufen auf der aktuellen Saison – das ist die, die die Uebersicht
  # ohne Parameter anzeigt.
  defp league(opts) do
    league_fixture(Keyword.put_new(opts, :season, Kits.current_season()))
  end

  describe "Raster" do
    test "zeigt Ligen nach tier und die Teams darunter", %{conn: conn} do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      league(competition: erste, team_count: 2)
      league(competition: zweite, team_count: 1)

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Erste Liga"
      assert html =~ "Zweite Liga"
      # Erstliga-Ueberschrift steht vor der Zweitliga-Ueberschrift.
      assert :binary.match(html, "Erste Liga") < :binary.match(html, "Zweite Liga")
      assert view |> element("h1") |> render() =~ "Jedes Trikot"
    end

    test "zeigt Kürzel und Name jedes Teams", %{conn: conn} do
      %{teams: [team | _]} = league(team_count: 1)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ team.name
      assert html =~ team.short_code
    end

    test "zeichnet ein Trikot ohne Bild als Silhouette", %{conn: conn} do
      league(team_count: 1, kit_types: ["home"])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(viewBox="0 0 100 110")
      assert html =~ "Platzhalter, kein Foto hinterlegt"
    end

    test "zeigt stattdessen das Bild, sobald eines hinterlegt ist", %{conn: conn} do
      team = team_fixture()
      competition = competition_fixture()

      {:ok, _} =
        Kits.create_team_season(%{
          team_id: team.id,
          competition_id: competition.id,
          season: Kits.current_season()
        })

      kit_fixture(
        team_id: team.id,
        kit_type: "home",
        cutout_url: "https://example.com/trikot.png"
      )

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "https://example.com/trikot.png"
    end

    test "sagt es, wenn für die Saison noch nichts hinterlegt ist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Noch keine Trikots"
    end
  end

  describe "Team-Modal" do
    setup do
      %{teams: [team | _]} = league(team_count: 1, kit_types: ["home", "away", "third"])
      %{team: team}
    end

    test "öffnet sich über die Kachel und zeigt alle Varianten", %{conn: conn, team: team} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element(~s{a[href="/teams/#{team.id}"]})
        |> render_click()

      assert html =~ team.name
      assert html =~ "Heim"
      assert html =~ "Auswärts"
      assert html =~ "Ausweich"
    end

    test "ist direkt verlinkbar", %{conn: conn, team: team} do
      {:ok, _view, html} = live(conn, ~p"/teams/#{team.id}")

      assert html =~ ~s(aria-modal="true")
      assert html =~ team.name
    end

    test "führt unbekannte Team-IDs zurück aufs Raster statt in einen Fehler", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/teams/999999")

      refute html =~ ~s(aria-modal="true")
    end
  end

  describe "Vergleich" do
    setup do
      %{kits: [a, b, c, d]} = league(team_count: 4, kit_types: ["home"])
      %{a: a, b: b, c: c, d: d}
    end

    test "nimmt ein Trikot auf und schreibt es in die URL", %{conn: conn, a: a} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element(~s{button[data-role="tile-compare"][phx-value-id="#{a.id}"]})
      |> render_click()

      assert_patched(view, "/?trikots=#{a.id}")
      assert render(view) =~ "noch eins dazu"
    end

    test "nimmt ein bereits gewähltes Trikot wieder heraus", %{conn: conn, a: a} do
      {:ok, view, _html} = live(conn, "/?trikots=#{a.id}")

      view
      |> element(~s{button[data-role="tray-remove"][phx-value-id="#{a.id}"]})
      |> render_click()

      assert_patched(view, "/")
    end

    test "lässt höchstens drei Trikots zu", %{conn: conn, a: a, b: b, c: c, d: d} do
      {:ok, view, _html} = live(conn, "/?trikots=#{a.id},#{b.id},#{c.id}")

      html =
        view
        |> element(~s{button[data-role="tile-compare"][phx-value-id="#{d.id}"]})
        |> render_click()

      assert html =~ "Im Vergleich haben drei Trikots Platz"
      refute render(view) =~ "trikots=#{a.id},#{b.id},#{c.id},#{d.id}"
    end

    test "blendet die Leiste erst ab dem ersten Trikot ein", %{conn: conn, a: a} do
      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "Leeren"

      {:ok, _view, html} = live(conn, "/?trikots=#{a.id}")
      assert html =~ "Leeren"
    end

    test "bietet das Öffnen erst ab zwei Trikots an", %{conn: conn, a: a, b: b} do
      {:ok, _view, html} = live(conn, "/?trikots=#{a.id}")
      refute html =~ "Vergleichen ("

      {:ok, _view, html} = live(conn, "/?trikots=#{a.id},#{b.id}")
      assert html =~ "Vergleichen (2)"
    end

    test "stellt im Modal alle gewählten Trikots gegenüber", %{conn: conn, a: a, b: b} do
      {:ok, _view, html} = live(conn, "/vergleich?trikots=#{a.id},#{b.id}")

      assert html =~ "Direktvergleich"
      assert html =~ "Liga"
      assert html =~ a.team_id |> Kits.get_team!() |> Map.fetch!(:name)
      assert html =~ b.team_id |> Kits.get_team!() |> Map.fetch!(:name)
    end

    test "behält die Auswahl beim Wechsel zwischen den Ansichten", %{
      conn: conn,
      a: a,
      b: b
    } do
      {:ok, view, _html} = live(conn, "/?trikots=#{a.id},#{b.id}")

      view |> element(~s{a[href="/vergleich?trikots=#{a.id}%2C#{b.id}"]}) |> render_click()

      assert_patched(view, "/vergleich?trikots=#{a.id}%2C#{b.id}")
    end

    test "der geteilte Link überlebt gelöschte oder fremde Trikots", %{conn: conn, a: a} do
      {:ok, _view, html} = live(conn, "/?trikots=#{a.id},999999,keine-zahl")

      # Das gueltige Trikot bleibt, der Rest faellt still weg.
      assert html =~ "Leeren"
      assert html =~ "noch 2 möglich"
    end

    test "'Leeren' setzt die Auswahl zurück", %{conn: conn, a: a, b: b} do
      {:ok, view, _html} = live(conn, "/?trikots=#{a.id},#{b.id}")

      view |> element("a", "Leeren") |> render_click()

      assert_patched(view, "/")
      refute render(view) =~ "Leeren"
    end
  end
end
