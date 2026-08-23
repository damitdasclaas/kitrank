defmodule KitrankWeb.StableRenderTest do
  @moduledoc """
  Zweimal dasselbe rendern muss zweimal dasselbe ergeben.

  Der Fehler, der das ausgelöst hat: ich hatte `System.unique_integer` in die
  ID eines `<img>` gesetzt, damit ein `phx-hook` dort greifen kann. Damit war
  die ID bei jedem Rendern anders — LiveView schickte bei jeder Eingabe
  achtzehn geänderte IDs, ersetzte jedes Bild im DOM und montierte jeden Hook
  neu. Das Diffing war ausgeschaltet, und jede Eingabe wurde teuer.

  Sichtbar war das nirgends: die Seite sah richtig aus, die Tests waren grün,
  und es fiel erst in Produktion auf. Deshalb ein Test, der zwei Durchgänge
  vergleicht statt einen zu prüfen.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  setup do
    %{teams: [team | _], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 2)

    # Eines mit Bild, eines ohne – die Silhouette hatte dasselbe Problem in
    # ihren Gradient-IDs.
    kit_fixture(
      team_id: team.id,
      season: season,
      kit_type: "special",
      cutout_url: "https://cdn.shopify.com/s/files/x.jpg"
    )

    %{team: team}
  end

  defp ids(html) do
    ~r/id="([^"]+)"/
    |> Regex.scan(html)
    |> Enum.map(&Enum.at(&1, 1))
    # Was Phoenix selbst pro Verbindung erzeugt, darf wechseln.
    |> Enum.reject(&String.starts_with?(&1, "phx-"))
    |> Enum.sort()
  end

  test "die Übersicht rendert zweimal identische IDs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    erst = ids(render(view))
    dann = ids(render(view))

    assert erst == dann, """
    Die IDs haben sich zwischen zwei Renderdurchgängen geändert.
    Das schaltet das Diffing aus: LiveView ersetzt jedes betroffene Element.

    neu:   #{inspect(dann -- erst)}
    weg:   #{inspect(erst -- dann)}
    """
  end

  test "auch nach einem Ereignis", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    vorher = ids(render(view))

    # Ein bestimmtes Trikot, nicht "irgendeinen Knopf" – mit zwei Vereinen
    # passen sonst beide auf den Selektor.
    [_, kit_id] = Regex.run(~r/phx-value-id="(\d+)"[^>]*data-role="tile-compare"/, render(view))
    render_click(view, "toggle_compare", %{"id" => kit_id})

    nachher = ids(render(view))

    # Die Vergleichsleiste kommt hinzu – aber nichts Bestehendes darf eine neue
    # ID bekommen.
    assert vorher -- nachher == [],
           "bestehende IDs sind verschwunden: #{inspect(vorher -- nachher)}"
  end

  test "die Vereinsansicht rendert zweimal identische IDs", %{conn: conn, team: team} do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}")

    assert ids(render(view)) == ids(render(view))
  end

  test "kein Bild trägt eine eigene ID", %{conn: conn} do
    # Die Ursache selbst, nicht nur die Wirkung: eine ID pro Bild braucht es
    # nur für ein phx-hook am <img>, und genau das war der Fehler. Der Rückfall
    # hängt jetzt an einem Zuhörer am Container.
    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ ~r/<img[^>]+id="/,
           "ein phx-hook am <img> braucht eine ID – das war der Auslöser"
  end

  test "der Rückfall hängt an einem festen Container", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(id="inhalt")
    assert html =~ ~s(phx-hook="ImageFallback")
  end

  test "der Wächter greift auch wirklich" do
    # Gegenprobe: sonst wäre nicht zu unterscheiden, ob die IDs stabil sind
    # oder ob der Vergleich ins Leere greift.
    a = ~s(<img id="kit-bild-1-100738"><div id="fest">)
    b = ~s(<img id="kit-bild-1-103042"><div id="fest">)

    assert ids(a) != ids(b)
    assert ids(a) == ids(a)
  end
end
