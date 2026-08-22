defmodule KitrankWeb.UntranslatedTextTest do
  @moduledoc """
  Wächter gegen deutschen Text, der nie durch Gettext läuft.

  Der Fall ist unangenehm, weil nichts kaputtgeht: eine nicht gewickelte
  Zeichenkette rendert einfach weiter auf Deutsch, und die englische Seite wird
  still zweisprachig. Kein Test, der auf Inhalte prüft, merkt das.

  Der Fingerabdruck sind Umlaute — die englische Fassung hat keine. Deshalb
  reicht es, die Besucher-Seiten auf Englisch zu rendern und nachzusehen, ob
  noch einer übrig ist. Eigennamen aus den Fixtures haben keine, sonst müsste
  hier eine Ausnahmeliste stehen.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Rankings

  @umlaute ~r/[äöüßÄÖÜ]/

  setup %{conn: conn} do
    %{teams: [team | _], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 2)

    {:ok, conn: init_test_session(conn, %{locale: "en"}), team: team, season: season}
  end

  # Skripte, Stile und SVG-Pfade sind kein Text für Leser.
  defp sichtbar(html) do
    html
    |> String.replace(~r{<(script|style|svg)\b.*?</\1>}s, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&[a-z]+;|&#\d+;/, " ")
  end

  defp deutsche_reste(html) do
    html
    |> sichtbar()
    |> then(&Regex.scan(~r/[\wÄÖÜäöüß]+/u, &1))
    |> Enum.map(&hd/1)
    |> Enum.filter(&Regex.match?(@umlaute, &1))
    |> Enum.uniq()
  end

  defp pruefe(html), do: assert(deutsche_reste(html) == [])

  test "die Übersicht", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    pruefe(html)
  end

  test "eine Vereinsseite", %{conn: conn, team: team} do
    {:ok, _view, html} = live(conn, ~p"/teams/#{team.id}")
    pruefe(html)
  end

  test "der Vergleich, auch leer", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/vergleich")
    pruefe(html)
  end

  test "eine neue Rangliste", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/rankings/new")
    pruefe(html)
  end

  test "die Auswahl und das Sortieren", %{conn: conn} do
    {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})

    for weg <- ["auswahl", "duell", "edit"] do
      {:ok, _view, html} = live(conn, "/rankings/#{ranking.edit_token}/#{weg}")
      pruefe(html)
    end
  end

  test "die Teilen-Ansicht", %{conn: conn} do
    {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})

    {:ok, _view, html} = live(conn, "/r/#{ranking.share_slug}")
    pruefe(html)
  end

  test "ein neuer Reveal-Raum", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/reveal/new")
    pruefe(html)
  end

  test "der Raum selbst", %{conn: conn, season: season} do
    {:ok, room} =
      Kitrank.Reveal.create_room(%{seasons: [season], kit_types: ["home"], max_participants: 4})

    {:ok, _view, html} = live(conn, "/reveal/#{room.room_code}")
    pruefe(html)
  end

  test "Anmeldung und Konto", %{conn: conn} do
    # Diese Seiten kamen aus dem Generator und waren englisch, während der Rest
    # deutsch war – jetzt ist Deutsch die Quelle und Englisch die Übersetzung.
    {:ok, _view, html} = live(conn, ~p"/users/log-in")
    pruefe(html)
  end

  test "der Wächter greift auch wirklich", %{conn: conn} do
    # Ohne Gegenprobe wäre nicht zu unterscheiden, ob nichts übrig ist oder ob
    # die Prüfung ins Leere greift.
    {:ok, _view, html} = live(conn, ~p"/")

    assert deutsche_reste(html <> "<p>Trikots auswählen</p>") == ["auswählen"]
  end
end
