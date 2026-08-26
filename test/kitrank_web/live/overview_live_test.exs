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

  # Seit alle Ligen zugeklappt starten, sieht ein frisch geladenes Raster keine
  # Kacheln. Tests, die welche brauchen, klappen erst eine auf.
  defp oeffne(view, competition) do
    view
    |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{competition.id}"]})
    |> render_click()
  end

  # Wenn es nur eine Liga gibt, muss der Test sie nicht benennen.
  defp oeffne(view) do
    view |> element(~s{button[phx-click="toggle_league"]}) |> render_click()
  end

  # Raster mit aufgeklappter Liga – der Ausgangspunkt fuer alles, was Kacheln
  # braucht.
  defp geoeffnet(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    {view, oeffne(view)}
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
      assert view |> element("h1") |> render() =~ "Welches Trikot"
    end

    test "sagt, dass es keine Provision gibt", %{conn: conn} do
      # Der Wettbewerber finanziert sich ueber Affiliate-Links zu Haendlern.
      # Wer an Kaeufen verdient, hat ein Interesse daran, wie das Ranking
      # ausgeht – deshalb steht das Gegenteil hier ausdruecklich.
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Keine Affiliate-Links, keine Provision."
      assert html =~ "verdient an keinem"
    end

    test "nennt im Kopf keine feste Liga", %{conn: conn} do
      # Die App soll weitere Ligen und Sportarten aufnehmen koennen – ein
      # fester Ligenname in Kopfzeile oder Ueberschrift waere dann als erstes
      # falsch. Die Ligen selbst stehen weiter an ihren Abschnitten.
      league(competition: competition_fixture(name: "Bundesliga", tier: 1), team_count: 1)

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Ranken, teilen, streiten"
      refute view |> element("h1") |> render() =~ "Bundesliga"
      # In der Abschnitts-Ueberschrift steht sie natuerlich weiterhin.
      assert html =~ "Bundesliga"
    end

    test "alle Ligen sind zunächst zu", %{conn: conn} do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      %{teams: [a]} = league(competition: erste, team_count: 1)
      %{teams: [b]} = league(competition: zweite, team_count: 1)

      {:ok, view, html} = live(conn, ~p"/")

      # Zu sehen ist die Liste der Ligen, nicht 18 Kacheln, die alles andere
      # unter den Bildschirmrand schieben. Geprueft wird ueber die
      # Kachel-Links: Namen aus Fixtures koennen Praefixe voneinander sein,
      # dann trifft ein refute versehentlich zu.
      assert html =~ "Erste Liga"
      assert html =~ "Zweite Liga"
      refute has_element?(view, ~s{a[href="/teams/#{a.id}"]})
      refute has_element?(view, ~s{a[href="/teams/#{b.id}"]})

      # Aufklappen zeigt sie dann.
      oeffne(view, erste)
      assert has_element?(view, ~s{a[href="/teams/#{a.id}"]})
      refute has_element?(view, ~s{a[href="/teams/#{b.id}"]})
    end

    test "eine andere Liga aufklappen klappt die vorige zu", %{conn: conn} do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      %{teams: [a]} = league(competition: erste, team_count: 1)
      %{teams: [b]} = league(competition: zweite, team_count: 1)

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{zweite.id}"]})
      |> render_click()

      assert has_element?(view, ~s{a[href="/teams/#{b.id}"]})
      refute has_element?(view, ~s{a[href="/teams/#{a.id}"]})
    end

    test "nochmal auf die offene Liga klappt sie zu", %{conn: conn} do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      %{teams: [a]} = league(competition: erste, team_count: 1)

      {:ok, view, _html} = live(conn, ~p"/")
      oeffne(view, erste)
      assert has_element?(view, ~s{a[href="/teams/#{a.id}"]})

      html = oeffne(view, erste)

      refute has_element?(view, ~s{a[href="/teams/#{a.id}"]})
      # Die Ueberschrift bleibt – die Seite wirkt nicht leer.
      assert html =~ "Erste Liga"
    end

    test "meldet den Zustand für Screenreader", %{conn: conn} do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      league(competition: erste, team_count: 1)
      league(competition: zweite, team_count: 1)

      {:ok, view, html} = live(conn, ~p"/")

      # Zu Anfang ist keine offen.
      refute html =~ ~s(aria-expanded="true")
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(aria-controls="liga-#{erste.id}")

      assert oeffne(view, erste) =~ ~s(aria-expanded="true")
    end

    test "zeigt Kürzel und Name jedes Teams", %{conn: conn} do
      %{teams: [team | _]} = league(team_count: 1)

      {:ok, view, _html} = live(conn, ~p"/")
      html = oeffne(view)

      assert html =~ team.name
      assert html =~ team.short_code
    end

    test "zeichnet ein Trikot ohne Bild als Silhouette", %{conn: conn} do
      league(team_count: 1, kit_types: ["home"])

      {:ok, view, _html} = live(conn, ~p"/")
      html = oeffne(view)

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

      {:ok, view, _html} = live(conn, ~p"/")
      html = oeffne(view)

      assert html =~ "https://example.com/trikot.png"
    end

    test "weist im Footer darauf hin, dass die App nicht offiziell ist", %{conn: conn} do
      # Kein Rechtsschutz, aber es wirkt gegen den Eindruck einer offiziellen
      # Verbindung – und genau darauf kommt es markenrechtlich an.
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "privates Projekt"
      assert html =~ "genannten Ligen, Verbänden oder Vereinen"
      assert html =~ "Marken gehören ihren Inhabern"
      assert html =~ ~s(href="/impressum")
      assert html =~ ~s(href="/datenschutz")
      assert html =~ ~s(href="https://github.com/damitdasclaas/kitrank")
    end

    test "sagt es, wenn für die Saison noch nichts hinterlegt ist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Noch keine Trikots"
    end
  end

  describe "Suche" do
    setup do
      liga = competition_fixture(name: "Erste Liga", tier: 1)
      andere = competition_fixture(sport_id: liga.sport_id, name: "Zweite Liga", tier: 2)

      # Namen fest, Kuerzel aus dem Fixture: short_code ist eindeutig, und zwei
      # async-Tests, die beide "KOE" anlegen, blockieren sich gegenseitig bis
      # Postgres einen Deadlock meldet.
      koeln = team_fixture(name: "1. FC Köln")
      dortmund = team_fixture(name: "Borussia Dortmund")
      hertha = team_fixture(name: "Hertha BSC")

      for {team, competition} <- [{koeln, liga}, {dortmund, liga}, {hertha, andere}] do
        {:ok, _} =
          Kits.create_team_season(%{
            team_id: team.id,
            competition_id: competition.id,
            season: Kits.current_season()
          })

        kit_fixture(team_id: team.id, kit_type: "home", season: Kits.current_season())
      end

      %{koeln: koeln, dortmund: dortmund, hertha: hertha, liga: liga, andere: andere}
    end

    defp suche(view, text) do
      view |> form("#verein-suche", %{"q" => text}) |> render_change()
    end

    # Der Vereinsname steht in der Kachel-Fusszeile als eigener Textknoten.
    defp kachel?(html, team), do: String.contains?(html, ">#{team.name}<")

    test "findet über den Namen", %{conn: conn, koeln: koeln, dortmund: dortmund} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = suche(view, "dortmund")

      assert kachel?(html, dortmund)
      refute kachel?(html, koeln)
    end

    test "findet über das Kürzel", %{conn: conn, dortmund: dortmund, koeln: koeln} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = suche(view, String.downcase(dortmund.short_code))

      assert kachel?(html, dortmund)
      refute kachel?(html, koeln)
    end

    test "achtet nicht auf Umlaute", %{conn: conn, koeln: koeln} do
      # Wer "koln" tippt, meint Köln — auf einer deutschen Tastatur ist der
      # Umlaut da, auf einer anderen nicht.
      {:ok, view, _html} = live(conn, ~p"/")

      assert kachel?(suche(view, "koln"), koeln)
      assert kachel?(suche(view, "KÖLN"), koeln)
    end

    test "der Ligenname holt die ganze Liga", %{
      conn: conn,
      koeln: koeln,
      dortmund: dortmund,
      hertha: hertha
    } do
      # "Bundesliga" einzutippen und dann keinen einzigen Verein zu sehen
      # waere seltsam.
      {:ok, view, _html} = live(conn, ~p"/")

      html = suche(view, "Erste Liga")

      assert kachel?(html, koeln)
      assert kachel?(html, dortmund)
      refute kachel?(html, hertha)
    end

    test "klappt auch zugeklappte Ligen auf", %{conn: conn, hertha: hertha} do
      # Hertha steht in der zweiten Liga, und die ist beim Laden zu. Ohne das
      # Aufklappen faende die Suche etwas, das man nicht sieht.
      {:ok, view, html} = live(conn, ~p"/")
      refute kachel?(html, hertha)

      assert kachel?(suche(view, "hertha"), hertha)
    end

    test "sagt, wie viele es sind", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert suche(view, "borussia") =~ "1 Verein"
      assert suche(view, "e") =~ "3 Vereine"
    end

    test "sagt es auch, wenn nichts passt", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = suche(view, "gibtsnicht")

      assert html =~ "Nichts gefunden"
      assert html =~ "gibtsnicht"
    end

    test "das Kreuz setzt zurück", %{conn: conn, koeln: koeln} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = suche(view, "dortmund")
      refute kachel?(html, koeln)

      html = view |> element(~s{[data-role="clear-search"]}) |> render_click()

      # Zurueck im Ausgangszustand: kein Kreuz mehr, und die Ligen sind wieder
      # zu – die Suche hatte sie nur fuer die Dauer der Suche aufgeklappt.
      refute html =~ ~s(data-role="clear-search")
      refute kachel?(html, koeln)
      assert html =~ "Erste Liga"
    end
  end

  describe "Vereine sortieren" do
    setup do
      liga = competition_fixture(name: "Erste Liga", tier: 1)

      # Kuerzel gleicher Laenge mit gemeinsamem Suffix: der erste Buchstabe
      # bestimmt die Reihenfolge, das Suffix macht sie ueber Tests hinweg
      # eindeutig. Feste Kuerzel waeren eine Kollision auf einer eindeutigen
      # Spalte — zwei async-Tests blockieren sich dann gegenseitig, bis
      # Postgres einen Deadlock meldet.
      lauf =
        System.unique_integer([:positive])
        |> rem(1_679_616)
        |> Integer.to_string(36)
        |> String.pad_leading(4, "0")

      # Absichtlich so gewaehlt, dass die Reihenfolge nach Kuerzel eine andere
      # ist als die alphabetische — sonst bewiese der Test nichts.
      vorgaben = [
        {"Zwickau", "A", ["home"]},
        {"Aachen", "M", ["home", "away", "third"]},
        {"Mainz", "Z", ["home", "away"]}
      ]

      for {name, praefix, kit_types} <- vorgaben do
        team = team_fixture(name: name, short_code: praefix <> lauf)

        {:ok, _} =
          Kits.create_team_season(%{
            team_id: team.id,
            competition_id: liga.id,
            season: Kits.current_season()
          })

        for kit_type <- kit_types do
          kit_fixture(team_id: team.id, kit_type: kit_type, season: Kits.current_season())
        end
      end

      :ok
    end

    # Die Reihenfolge, in der die Vereinsnamen im HTML stehen.
    defp reihenfolge(html) do
      ["Aachen", "Mainz", "Zwickau"]
      |> Enum.map(fn name -> {:binary.match(html, ">#{name}<"), name} end)
      |> Enum.reject(fn {treffer, _name} -> treffer == :nomatch end)
      |> Enum.sort_by(fn {{start, _laenge}, _name} -> start end)
      |> Enum.map(fn {_treffer, name} -> name end)
    end

    defp sortiere(view, key) do
      view |> element(~s{[data-role="sort-teams"][phx-value-by="#{key}"]}) |> render_click()
    end

    test "steht zunächst alphabetisch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = oeffne(view)

      assert reihenfolge(html) == ["Aachen", "Mainz", "Zwickau"]
    end

    test "nochmal auf dieselbe dreht um", %{conn: conn} do
      {view, _html} = geoeffnet(conn)

      assert reihenfolge(sortiere(view, "name")) == ["Zwickau", "Mainz", "Aachen"]
      assert reihenfolge(sortiere(view, "name")) == ["Aachen", "Mainz", "Zwickau"]
    end

    test "nach Kürzel", %{conn: conn} do
      {view, _html} = geoeffnet(conn)

      # A… Zwickau, M… Aachen, Z… Mainz — nicht die alphabetische Reihenfolge.
      assert reihenfolge(sortiere(view, "code")) == ["Zwickau", "Aachen", "Mainz"]
    end

    test "nach Trikots — die meisten zuerst", %{conn: conn} do
      # Ein Wechsel des Schlüssels fängt bei dessen natürlicher Richtung an.
      # Bei „Trikots" ist das absteigend: 3, 2, 1.
      {view, _html} = geoeffnet(conn)

      assert reihenfolge(sortiere(view, "kits")) == ["Aachen", "Mainz", "Zwickau"]
      assert reihenfolge(sortiere(view, "kits")) == ["Zwickau", "Mainz", "Aachen"]
    end

    test "die aktive Sortierung zeigt ihre Richtung", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "hero-arrow-up-mini"
      refute html =~ "hero-arrow-down-mini"

      assert sortiere(view, "name") =~ "hero-arrow-down-mini"
    end
  end

  describe "Trikot-Variante umschalten" do
    setup do
      %{teams: [a, b], kits: kits, competition: competition} =
        league(team_count: 2, kit_types: ["home", "away", "third"])

      %{a: a, b: b, kits: kits, competition: competition}
    end

    # Der Vergleich-Knopf der Kachel traegt die ID des gerade gezeigten
    # Trikots – daran laesst sich ablesen, welche Variante die Kachel zeigt.
    defp zeigt?(html, kit) do
      html =~ ~s(phx-value-id="#{kit.id}" data-role="tile-compare")
    end

    defp trikot(kits, team, kit_type) do
      Enum.find(kits, &(&1.team_id == team.id and &1.kit_type == kit_type))
    end

    test "zeigt zunaechst das Heimtrikot", %{conn: conn, a: a, b: b, kits: kits} do
      {_view, html} = geoeffnet(conn)

      assert zeigt?(html, trikot(kits, a, "home"))
      assert zeigt?(html, trikot(kits, b, "home"))
      refute zeigt?(html, trikot(kits, a, "away"))
    end

    test "ein Klick auf das Kuerzel schaltet nur diese Kachel um", %{
      conn: conn,
      a: a,
      b: b,
      kits: kits
    } do
      {view, _html} = geoeffnet(conn)

      html =
        view
        |> element(~s{[data-role="tile-kit"][phx-value-team="#{a.id}"][phx-value-type="away"]})
        |> render_click()

      assert zeigt?(html, trikot(kits, a, "away"))
      # Der andere Verein bleibt, wo er war.
      assert zeigt?(html, trikot(kits, b, "home"))
    end

    test "der Schalter im Kopf stellt alle auf einmal um", %{
      conn: conn,
      a: a,
      b: b,
      kits: kits
    } do
      {view, _html} = geoeffnet(conn)

      html =
        view
        |> element(~s{[data-role="show-all-kits"][phx-value-type="third"]})
        |> render_click()

      assert zeigt?(html, trikot(kits, a, "third"))
      assert zeigt?(html, trikot(kits, b, "third"))
    end

    test "alle auf einmal raeumt die einzeln gewaehlten weg", %{conn: conn, a: a, kits: kits} do
      {view, _html} = geoeffnet(conn)

      view
      |> element(~s{[data-role="tile-kit"][phx-value-team="#{a.id}"][phx-value-type="away"]})
      |> render_click()

      html =
        view
        |> element(~s{[data-role="show-all-kits"][phx-value-type="home"]})
        |> render_click()

      # Sonst bliebe die Ansicht gemischt, ohne dass man sieht warum.
      assert zeigt?(html, trikot(kits, a, "home"))
      refute zeigt?(html, trikot(kits, a, "away"))
    end

    test "ein Verein ohne diese Variante faellt aufs Heimtrikot zurueck", %{
      conn: conn,
      competition: competition
    } do
      # Nur Heim – dieser Verein kann kein Ausweichtrikot zeigen. In dieselbe
      # Liga, denn nur die oberste ist aufgeklappt.
      %{kits: [nur_heim]} =
        league(competition: competition, team_count: 1, kit_types: ["home"])

      {view, _html} = geoeffnet(conn)

      html =
        view
        |> element(~s{[data-role="show-all-kits"][phx-value-type="third"]})
        |> render_click()

      # Keine Luecke im Raster.
      assert zeigt?(html, nur_heim)
    end

    test "der Schalter zeigt nur Varianten, die es in der Saison gibt", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(phx-value-type="home" data-role="show-all-kits")
      assert html =~ ~s(phx-value-type="third" data-role="show-all-kits")
      # Sondertrikots gibt es hier keine – ein Schalter dafuer taete nichts.
      refute html =~ ~s(phx-value-type="special")
    end

    test "das Kuerzel des gezeigten Trikots ist als gedrueckt gemeldet", %{conn: conn, a: a} do
      {view, _html} = geoeffnet(conn)

      html =
        view
        |> element(~s{[data-role="tile-kit"][phx-value-team="#{a.id}"][phx-value-type="away"]})
        |> render_click()

      assert html =~
               ~s(phx-value-team="#{a.id}" phx-value-type="away" data-role="tile-kit" aria-pressed="true")
    end

    test "die Kuerzel liegen ueber dem Kachel-Link, sonst faengt der die Klicks ab", %{conn: conn} do
      {_view, html} = geoeffnet(conn)

      # Der Link deckt die Kachel mit z-10 ab; die Leiste braucht mehr.
      assert html =~ ~r/class="relative z-20 ml-auto flex shrink-0 gap-1"/
    end
  end

  describe "Team-Modal" do
    setup do
      %{teams: [team | _]} = league(team_count: 1, kit_types: ["home", "away", "third"])
      %{team: team}
    end

    test "öffnet sich über die Kachel und zeigt alle Varianten", %{conn: conn, team: team} do
      {view, _html} = geoeffnet(conn)

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

  describe "Große Ansicht" do
    setup do
      %{teams: [team], kits: [kit]} =
        league_fixture(season: Kits.current_season(), team_count: 1, kit_types: ["home"])

      {:ok, kit} =
        Kits.update_kit(kit, %{
          cutout_url: "https://example.com/cutout.jpg",
          model_image_urls: ["https://example.com/model-a.jpg", "https://example.com/model-b.jpg"]
        })

      %{team: team, kit: kit}
    end

    test "öffnet sich aus dem Team-Modal", %{conn: conn, team: team, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

      html =
        view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      assert html =~ ~s(id="kit-lightbox")
      assert html =~ "https://example.com/cutout.jpg"
      assert html =~ "1 / 3"
    end

    test "startet bei dem Bild, das die kleine Ansicht gerade zeigt", %{
      conn: conn,
      team: team,
      kit: kit
    } do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

      # Auf das zweite Bild umschalten, dann vergroessern.
      view
      |> element(~s{button[phx-click="select_image"][phx-value-index="1"]})
      |> render_click()

      html =
        view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      assert html =~ "2 / 3"
      assert html =~ "https://example.com/model-a.jpg"
    end

    test "blättert vor und zurück und läuft dabei um", %{conn: conn, team: team, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")
      view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      html = view |> element(~s{button[phx-value-delta="1"]}) |> render_click()
      assert html =~ "2 / 3"

      html = view |> element(~s{button[phx-value-delta="1"]}) |> render_click()
      assert html =~ "3 / 3"

      # Ueber das Ende hinaus geht es wieder von vorn los.
      html = view |> element(~s{button[phx-value-delta="1"]}) |> render_click()
      assert html =~ "1 / 3"

      html = view |> element(~s{button[phx-value-delta="-1"]}) |> render_click()
      assert html =~ "3 / 3"
    end

    test "die kleine Ansicht steht danach auf demselben Bild", %{
      conn: conn,
      team: team,
      kit: kit
    } do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")
      view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()
      view |> element(~s{button[phx-value-delta="1"]}) |> render_click()

      html = view |> element(~s{button[phx-click="zoom_close"]}) |> render_click()

      refute html =~ ~s(id="kit-lightbox")

      # Die kleine Galerie steht auf demselben Bild – jetzt ein Vorschaubild
      # statt eines Strichs.
      assert has_element?(view, ~s{button[phx-value-index="1"][aria-current="true"]})
    end

    test "Escape schließt erst die große Ansicht, nicht gleich das Modal", %{
      conn: conn,
      team: team,
      kit: kit
    } do
      {:ok, view, html} = live(conn, ~p"/teams/#{team.id}")
      # Solange nichts darueber liegt, schliesst Escape das Modal.
      assert html =~ ~s(phx-key="Escape")

      html =
        view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      # Jetzt nicht mehr – sonst waeren beide gleichzeitig weg.
      refute html =~ ~s(phx-key="Escape")

      html = view |> element("#kit-lightbox") |> render_keydown(%{"key" => "Escape"})

      refute html =~ ~s(id="kit-lightbox")
      assert html =~ ~s(aria-modal="true")
      assert html =~ team.name
    end

    test "Pfeiltasten blättern", %{conn: conn, team: team, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")
      view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      html = view |> element("#kit-lightbox") |> render_keydown(%{"key" => "ArrowRight"})
      assert html =~ "2 / 3"

      html = view |> element("#kit-lightbox") |> render_keydown(%{"key" => "ArrowLeft"})
      assert html =~ "1 / 3"
    end

    test "funktioniert auch für Trikots ohne Foto", %{conn: conn} do
      %{teams: [team], kits: [kit]} =
        league_fixture(season: Kits.current_season(), team_count: 1, kit_types: ["away"])

      {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

      html =
        view |> element(~s{button[phx-click="zoom"][phx-value-id="#{kit.id}"]}) |> render_click()

      assert html =~ ~s(id="kit-lightbox")
      assert html =~ "noch kein Foto hinterlegt"
      # Kein Blaettern, wenn es nur die Zeichnung gibt.
      refute html =~ ~s(phx-value-delta="1")
    end

    test "lässt sich auch aus dem Vergleich öffnen", %{conn: conn, kit: kit} do
      %{kits: [other]} =
        league_fixture(season: Kits.current_season(), team_count: 1, kit_types: ["home"])

      {:ok, view, _html} = live(conn, "/vergleich?trikots=#{kit.id},#{other.id}")

      # Der Vergleich rendert zwei Layouts – eins fuers Handy, eins ab sm.
      # Beide zeigen dasselbe Trikot, also braucht der Test die Rolle dazu.
      html =
        view
        |> element(~s{[data-role="compare-zoom"][phx-value-id="#{kit.id}"]})
        |> render_click()

      assert html =~ ~s(id="kit-lightbox")
      assert html =~ "https://example.com/cutout.jpg"
    end
  end

  describe "Vergleich" do
    setup do
      %{kits: [a, b, c, d]} = league(team_count: 4, kit_types: ["home"])
      %{a: a, b: b, c: c, d: d}
    end

    test "nimmt ein Trikot auf und schreibt es in die URL", %{conn: conn, a: a} do
      {view, _html} = geoeffnet(conn)

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
      oeffne(view)

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

    test "der Vergleich-Knopf steht auf dem Handy da, nicht erst beim Hovern", %{conn: conn} do
      {_view, html} = geoeffnet(conn)

      [knopf] = Regex.run(~r/<button[^>]*data-role="tile-compare"[^>]*>/, html)

      # Ohne Praefix gilt eine Klasse ab dem kleinsten Bildschirm. Ein nacktes
      # opacity-0 heisst also: auf dem Handy unsichtbar, und dort gibt es kein
      # Hover, das sie zurueckholt.
      refute knopf =~ ~r/class="[^"]*(^|\s)opacity-0/
      assert knopf =~ "sm:opacity-0"
      assert knopf =~ "sm:group-hover:opacity-100"
    end

    test "der Vergleich fuellt auf dem Handy den Bildschirm", %{conn: conn, a: a, b: b} do
      {:ok, _view, html} = live(conn, "/vergleich?trikots=#{a.id},#{b.id}")

      # Randlos und ueber die volle Hoehe – sonst passen zwei Trikots nicht
      # nebeneinander auf ein 390er Display.
      assert html =~ "min-h-[100dvh]"
      assert html =~ ~s(data-role="compare-zoom-mobile")

      # Und die Tabelle mit ihren 560 px liegt auf dem Handy nicht davor.
      assert html =~ ~r/class="hidden overflow-x-auto[^"]*sm:block/
    end

    test "beide Trikots stehen auf dem Handy nebeneinander", %{conn: conn, a: a, b: b} do
      {:ok, _view, html} = live(conn, "/vergleich?trikots=#{a.id},#{b.id}")

      spalten = Regex.scan(~r/data-role="compare-zoom-mobile"/, html)

      assert length(spalten) == 2
      assert html =~ "grid-template-columns: repeat(2, minmax(0, 1fr))"
    end

    test "aus dem Vergleich fuehrt ein Weg ins Detail", %{conn: conn, a: a, b: b} do
      team = Kits.get_team!(a.team_id)
      {:ok, view, html} = live(conn, "/vergleich?trikots=#{a.id},#{b.id}")

      assert html =~ "/teams/#{team.id}?trikots=#{a.id}%2C#{b.id}&amp;zurueck=vergleich"

      # Je Spalte einer – dieser gehoert zu a.
      html =
        view
        |> element(~s{[data-role="compare-detail"][href^="/teams/#{team.id}?"]})
        |> render_click()

      # Das Detail zeigt, was der Vergleich nicht hat: alle Trikots des
      # Vereins und den Weg in den Shop.
      assert html =~ team.name
      assert html =~ "Vereinsshop"
    end

    test "und aus dem Detail wieder zurueck in den Vergleich", %{conn: conn, a: a, b: b} do
      team = Kits.get_team!(a.team_id)

      {:ok, _view, html} =
        live(conn, "/teams/#{team.id}?trikots=#{a.id},#{b.id}&zurueck=vergleich")

      assert html =~ "/vergleich?trikots=#{a.id}%2C#{b.id}"
    end

    test "ohne diese Spur schliesst das Detail auf die Uebersicht", %{conn: conn, a: a} do
      team = Kits.get_team!(a.team_id)

      {:ok, _view, html} = live(conn, "/teams/#{team.id}?trikots=#{a.id}")

      refute html =~ "/vergleich?"
    end

    test "steht nach dem Detail nur noch eins im Vergleich, geht es zur Uebersicht", %{
      conn: conn,
      a: a
    } do
      # Sonst landet man auf einem Vergleich, der nichts vergleicht.
      team = Kits.get_team!(a.team_id)

      {:ok, _view, html} = live(conn, "/teams/#{team.id}?trikots=#{a.id}&zurueck=vergleich")

      refute html =~ "/vergleich?"
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
