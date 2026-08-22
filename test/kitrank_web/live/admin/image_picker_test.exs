defmodule KitrankWeb.Admin.ImagePickerTest do
  @moduledoc """
  Produktlink einfügen, Bilder anklicken. Die Reihenfolge der Klicks bestimmt,
  welches Bild der Freisteller ist — das prüft dieser Test, weil es der einzige
  Teil ist, den kein Skript für dich entscheidet.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.AccountsFixtures
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  # Dieselben Bilder, die der Stub liefert.
  @a "https://example.com/a.jpg"
  @b "https://example.com/b.jpg"
  @c "https://example.com/c.jpg"

  test "der Stub liefert genau diese Bilder" do
    assert Kitrank.Kits.ProductImagesStub.images() == [@a, @b, @c]
  end

  setup %{conn: conn} do
    %{teams: [team], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 1, kit_types: [])

    kit = kit_fixture(team_id: team.id, season: season, kit_type: "home")

    conn = log_in_user(conn, admin_fixture())
    {:ok, view, _html} = live(conn, ~p"/admin/trikots/#{kit.id}")
    hole_bilder(view, "https://stub/produkt/1")

    %{view: view, kit: kit}
  end

  # Der Abruf laeuft in einem eigenen Prozess, damit ein blockender Shop die
  # Oberflaeche nicht einfriert. Im Test heisst das: ausloesen und auf das
  # Ergebnis warten, sonst rendert man den Zwischenstand.
  #
  # Ueber das echte Formular, nicht ueber render_hook: der Handler allein
  # aufgerufen haette den Fehler nie gezeigt, an dem es in Produktion
  # gescheitert ist – das Feld wurde gar nicht mitgeschickt.
  defp hole_bilder(view, url) do
    view |> form("#image-picker-form", %{"product_url" => url}) |> render_submit()
    render_async(view)
  end

  defp klick(view, url) do
    view
    |> element(~s{button[phx-click="toggle_image"][phx-value-url="#{url}"]})
    |> render_click()
  end

  test "das Eingabefeld liegt in einem eigenen Formular, nicht im Trikot-Formular" do
    # Sonst kommt der eingegebene Link nie beim Server an – und verschachtelte
    # Formulare waeren ohnehin ungueltiges HTML.
    quelle = File.read!("lib/kitrank_web/live/admin/kit_live.ex")

    assert quelle =~ ~s(<form id="image-picker-form" phx-submit="fetch_images")
    assert :binary.match(quelle, "<.image_picker") < :binary.match(quelle, ~s(id="kit-form"))
  end

  test "zeigt die Kandidaten zum Anklicken", %{view: view} do
    html = render(view)

    assert html =~ "3 Bilder gefunden, 0 gewählt"
    assert html =~ @a
    assert html =~ ~s{phx-click="toggle_image"}
  end

  test "die Klick-Reihenfolge legt die Rollen fest", %{view: view} do
    # Konvention der Datenpflege: 1 Vorderseite, 2 Rueckseite, ab 3 Model.
    html = klick(view, @b)
    assert html =~ "Vorderseite"
    assert html =~ "3 Bilder gefunden, 1 gewählt"

    html = klick(view, @a)
    assert html =~ "Rückseite"
    assert html =~ "3 Bilder gefunden, 2 gewählt"

    html = klick(view, @c)
    assert html =~ "Model 1"
  end

  test "speichert in der Klick-Reihenfolge", %{view: view, kit: kit} do
    klick(view, @c)
    klick(view, @a)
    klick(view, @b)

    view |> form("#kit-form") |> render_submit()

    gespeichert = Kits.get_kit!(kit.id)
    assert gespeichert.cutout_url == @c
    assert gespeichert.model_image_urls == [@a, @b]
  end

  test "nochmal klicken nimmt das Bild wieder raus", %{view: view} do
    klick(view, @a)
    klick(view, @b)
    html = klick(view, @a)

    assert html =~ "3 Bilder gefunden, 1 gewählt"
    # Jetzt rutscht b auf die Vorderseite, weil a weg ist. Auf das Fehlen von
    # "Rückseite" kann man hier nicht pruefen – die Hinweiszeile nennt beide.
    assert html =~ "Vorderseite"
  end

  test "'Auswahl leeren' setzt alles zurück", %{view: view} do
    klick(view, @a)
    klick(view, @b)

    html = view |> element(~s{button[phx-click="clear_images"]}) |> render_click()

    assert html =~ "3 Bilder gefunden, 0 gewählt"
  end

  test "übernimmt den Produktlink gleich als Shop-Deep-Link", %{view: view, kit: kit} do
    klick(view, @a)
    view |> form("#kit-form") |> render_submit()

    assert Kits.get_kit!(kit.id).source_shop_url == "https://stub/produkt/1"
  end

  test "eine bestehende Auswahl ist beim Öffnen markiert", %{conn: conn} do
    %{teams: [team], season: season} =
      league_fixture(season: Kits.current_season(), team_count: 1, kit_types: [])

    kit =
      kit_fixture(
        team_id: team.id,
        season: season,
        kit_type: "away",
        cutout_url: @a,
        model_image_urls: [@b]
      )

    conn = log_in_user(conn, admin_fixture())
    {:ok, view, _html} = live(conn, ~p"/admin/trikots/#{kit.id}")

    assert hole_bilder(view, "https://stub/produkt/2") =~ "2 gewählt"
  end

  describe "Fehlerfälle" do
    test "meldet, wenn der Shop den Abruf ablehnt", %{view: view} do
      assert hole_bilder(view, "https://stub/blockiert") =~ "lässt automatisierte Abrufe nicht zu"
    end

    test "meldet eine unbrauchbare Adresse", %{view: view} do
      assert hole_bilder(view, "kein-link") =~ "http://"
    end

    test "meldet eine Seite ohne Bilder", %{view: view} do
      assert hole_bilder(view, "https://stub/leer") =~ "keine Bilder zu finden"
    end

    test "erklärt einen Timeout, statt nur 'nicht erreichbar' zu sagen", %{view: view} do
      html = hole_bilder(view, "https://stub/timeout")

      assert html =~ "hat nicht geantwortet"
      # Und sagt, was man stattdessen tun kann.
      assert html =~ "Rechtsklick"
    end

    test "erklärt eine Seite, die ihre Bilder erst im Browser lädt", %{view: view} do
      assert hole_bilder(view, "https://stub/js") =~ "erst im Browser nach"
    end
  end
end
