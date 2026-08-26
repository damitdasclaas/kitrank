defmodule KitrankWeb.ImageContainmentTest do
  @moduledoc """
  Dass Trikotbilder in ihrem Kasten bleiben.

  Der Fall: auf iOS Safari liefen die Bilder über den Rand. Ursache war
  `h-full w-full` im Fluss plus `width="400" height="400"` am Bild — in einem
  Flex-Container mit `aspect-ratio` löst Safari die Prozenthöhe nicht immer
  auf, die Höhe wird `auto`, und das Bild nimmt seine Eigengröße. In einer
  170 Pixel breiten Kachel läuft es damit hinaus.

  Diese Tests prüfen Klassen, nicht Pixel — ein echtes Gerät ersetzen sie
  nicht. Sie halten die Entscheidung fest, damit sie nicht beim nächsten
  Umbau still zurückgedreht wird.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  setup %{conn: conn} do
    %{teams: [team | _], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 2)

    # Ohne Bild zeichnet kit_figure die Silhouette – dann gibt es kein <img>,
    # an dem sich etwas prüfen liesse.
    for kit <- Kits.list_kits(season) do
      {:ok, _} =
        Kits.update_kit(kit, %{"cutout_url" => "https://cdn.shopify.com/s/files/#{kit.id}.jpg"})
    end

    # Ligen starten zugeklappt – ohne Aufklappen gibt es kein <img>, an dem
    # sich etwas pruefen liesse.
    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> element(~s{button[phx-click="toggle_league"]}) |> render_click()

    %{view: view, html: html, team: team}
  end

  test "das Bild misst gegen seinen Kasten, nicht über eine Prozentkette", %{html: html} do
    assert html =~ "absolute inset-0 h-full w-full object-contain"
  end

  test "und trägt keine festen Maße", %{html: html} do
    # width/height am Bild sollten den Layout-Sprung verhindern. Den verhindert
    # aber schon das feste Seitenverhältnis der Kachel — und als Zahlenpaar
    # wären sie falsch: das TSG-Trikot ist 378x515, nicht quadratisch.
    refute html =~ ~r/<img[^>]+width="400"/
    refute html =~ ~r/<img[^>]+height="400"/
  end

  test "der umgebende Kasten ist relativ", %{html: html} do
    # Ohne `relative` misst `inset-0` gegen den nächsten positionierten
    # Vorfahren — irgendwo weit oben, und das Bild deckt die halbe Seite ab.
    # Das `relative` sitzt jetzt beim Aufrufer, nicht mehr an kit_figure: in
    # `fill`-Modus legt sich der Wrapper selbst mit `absolute inset-0` in den
    # Kasten, also muss der Kasten der positionierte Vorfahre sein.
    assert html =~ ~r/class="relative flex aspect-\[4\/3\][^"]*overflow-hidden/
    assert html =~ "absolute inset-0 flex items-center justify-center"
  end

  test "jeder Aufrufer gibt dem Kasten eine Größe" do
    # Das Bild steht nicht mehr im Fluss, also kann es die Höhe nicht liefern.
    # Ein Aufrufer ohne Höhenangabe bekommt einen Kasten von null Pixeln.
    quellen =
      Path.wildcard("lib/kitrank_web/**/*.ex")
      |> Enum.map(&{&1, File.read!(&1)})

    ohne_groesse =
      for {pfad, quelle} <- quellen,
          [aufruf] <- Regex.scan(~r/<\.kit_figure\b[^>]*?\/>/s, quelle),
          not Regex.match?(~r/class="[^"]*\bh-(?:full|\d|\[)/, aufruf),
          # `fill` ist der andere gueltige Weg: dort kommt die Groesse nicht vom
          # Bild, sondern vom Kasten, der es traegt.
          not Regex.match?(~r/\bfill\b/, aufruf),
          do: {pfad, aufruf |> String.replace(~r/\s+/, " ") |> String.slice(0, 90)}

    assert ohne_groesse == []
  end

  test "die Lupe bleibt eigen begrenzt", %{view: view, html: html} do
    # Sie steht bewusst nicht in einem Kasten mit Seitenverhältnis, sondern
    # begrenzt sich selbst gegen den Bildschirm.
    [_, kit_id] = Regex.run(~r/phx-value-id="(\d+)"[^>]*data-role="tile-compare"/, html)

    gross = render_click(view, "zoom", %{"id" => kit_id})

    assert gross =~ "max-h-[72vh]"
    refute gross =~ ~r/<img[^>]+class="absolute inset-0[^"]*"[^>]*max-h-\[72vh\]/
  end
end
