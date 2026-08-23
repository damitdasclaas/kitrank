defmodule KitrankWeb.MobileLayoutTest do
  @moduledoc """
  Was auf dem kleinen Bildschirm passiert.

  Der Fall, der das ausgelöst hat: das Detail-Modal sprang erst ab `sm:` auf
  zwei Spalten. Auf einem 390-px-Gerät war die Bildfläche damit 302 px groß —
  mehr als die 192 px am Rechner. Das Detail war auf dem kleinen Gerät größer
  als auf dem großen, und jedes Trikot füllte einen Bildschirm.

  Solche Fehler sind mit Tailwind eindeutig prüfbar, weil die Breakpoints im
  Klassennamen stehen: fehlt der Präfix, gilt die Klasse ab null Pixel. Ein
  Test auf gerenderte Klassen ist hier kein Ersatz für einen Blick, aber er
  hält die Entscheidung fest.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Rankings

  setup do
    %{teams: [team], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 1)

    %{team: team, season: season}
  end

  describe "Detail eines Vereins" do
    test "zeigt schon auf dem Handy zwei Spalten", %{conn: conn, team: team} do
      {:ok, _view, html} = live(conn, ~p"/teams/#{team.id}")

      assert html =~ "grid grid-cols-2 gap-px bg-line lg:grid-cols-3"

      refute html =~ "grid gap-px bg-line sm:grid-cols-2",
             "eine Spalte auf dem Handy macht das Detail größer als am Rechner"
    end

    test "das Polster der Bildfläche wächst erst mit dem Bildschirm", %{conn: conn, team: team} do
      {:ok, _view, html} = live(conn, ~p"/teams/#{team.id}")

      assert html =~ "justify-center p-4 sm:p-8"
    end

    test "die Fußzeile der Kachel bricht auf dem Handy um", %{conn: conn, team: team} do
      # Bei zwei Spalten sind es 183 px – Beschriftung und Knopf passen dort
      # nicht nebeneinander.
      {:ok, _view, html} = live(conn, ~p"/teams/#{team.id}")

      assert html =~ "flex flex-col items-start gap-2 border-t border-line px-4 py-3 sm:flex-row"
    end
  end

  describe "Detail beim Sortieren" do
    setup %{team: team, season: season} do
      # Sondertrikot: league_fixture hat Heim, Auswärts und Ausweich schon
      # angelegt, und davon gibt es je Saison nur eines.
      kit =
        kit_fixture(
          team_id: team.id,
          season: season,
          kit_type: "special",
          cutout_url: "https://cdn.shopify.com/s/x.jpg"
        )

      {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})
      1 = Rankings.add_kits(ranking, [kit.id])

      %{ranking: ranking}
    end

    test "lädt nicht das Original in eine Kachel von 300 px", %{conn: conn, ranking: ranking} do
      # Das war der Fehler wörtlich: size={:full}. Bei TSG waren das 1200x1200
      # und 304 kB für eine Fläche, die keine 400 px breit ist. Das Original
      # gehört in die Lupe.
      {:ok, view, _html} = live(conn, "/rankings/#{ranking.edit_token}/edit")

      html = view |> element(~s{[data-role="detail-link"]}) |> render_click()

      assert html =~ "width=400", "die Detailkachel soll die kleine Variante nehmen"
      refute html =~ "width=2048"
    end

    test "die Bildfläche ist auf dem Handy flacher als quadratisch", %{
      conn: conn,
      ranking: ranking
    } do
      {:ok, view, _html} = live(conn, "/rankings/#{ranking.edit_token}/edit")

      html = view |> element(~s{[data-role="detail-link"]}) |> render_click()

      assert html =~ "aspect-[4/3] items-center justify-center rounded-tl-xl p-4 sm:aspect-square"
    end
  end

  describe "Kopfzeile" do
    test "der Theme-Umschalter erscheint erst ab sm", %{conn: conn} do
      # Die Rechnung, um die es geht: Logo 85 + Ranglisten 72 + Reveal 68 +
      # Sprachen 52 + Theme 96 + Abstände 52 + Rand 32 ≈ 457 px. Auf einem
      # 390er Display war damit die *Seite* breiter als der Bildschirm und
      # scrollte seitlich — es sah aus, als liefe der Inhalt über den Rand.
      #
      # Der Theme-Umschalter ist die entbehrlichste der fünf Gruppen: ohne ihn
      # folgt die Darstellung der Systemeinstellung.
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~r/class="card relative hidden[^"]*\bsm:flex\b/
    end

    test "sie bricht nicht um, sondern lässt schrumpfen", %{conn: conn} do
      # Eine umbrechende Kopfzeile wäre höher als h-14 und würde unter der
      # Sticky-Leiste hängen.
      {:ok, _view, html} = live(conn, ~p"/")

      kopf = Regex.run(~r/<header.*?<\/header>/s, html) |> hd()

      refute kopf =~ "flex-wrap"
      assert kopf =~ "shrink-0"
      assert kopf =~ "min-w-0"
    end

    test "auf dem Handy engere Abstände als am Rechner", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "gap-3 px-4 sm:gap-4"
    end
  end

  test "die Lupe bleibt der Ort für das Original", %{team: team, season: season} do
    # Gegenprobe: irgendwo muss das grosse Bild ja hin, sonst hätte ich die
    # Qualität abgeschafft statt die Bytes.
    kit_fixture(
      team_id: team.id,
      season: season,
      kit_type: "special",
      cutout_url: "https://cdn.shopify.com/s/y.jpg"
    )

    quelle = File.read!("lib/kitrank_web/components/kit_components.ex")

    assert quelle =~ ":full)"
    assert quelle =~ "max-h-[72vh]", "und begrenzt bleibt sie trotzdem"
  end
end
