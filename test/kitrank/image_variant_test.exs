defmodule Kitrank.ImageVariantTest do
  @moduledoc """
  Die Größenregeln je Shop-CDN.

  Warum das Tests verdient: die Regeln sind gemessene Einzelfälle, keine
  Systematik. Wird eine davon versehentlich verallgemeinert, merkt es niemand —
  im schlimmsten Fall wird die Seite langsamer statt schneller. Bei Schalke
  liefert `?width=400` statt 339 kB AVIF ganze 2520 kB PNG.
  """
  use ExUnit.Case, async: true

  doctest Kitrank.Kits.ImageVariant, import: true

  alias Kitrank.Kits.ImageVariant

  describe "unbekannte Hosts" do
    test "bleiben unangetastet" do
      for url <- [
            "https://beispiel.de/bild.jpg",
            "https://shop.irgendwas.de/media/x/y.png?v=1",
            "https://prod-api.tsg-hoffenheim.de/medias/1200Wx1200H-104590-Front.png"
          ] do
        assert ImageVariant.url(url, :thumb) == url
        assert ImageVariant.url(url, :medium) == url
      end
    end

    test "Schalke bekommt nie einen width-Parameter" do
      # Der Parameter wird dort ignoriert und die Antwort wechselt von AVIF auf
      # PNG — aus 339 kB werden 2520 kB. Über /thumbnail/ geht es dagegen (siehe
      # unten). Derselbe Host, zwei Verfahren, entgegengesetztes Ergebnis.
      ergebnis = ImageVariant.url("https://shop.schalke04.de/media/heimtrikot.png", :thumb)

      refute ergebnis =~ "width="
    end

    test "kein Host, kein Unsinn" do
      assert ImageVariant.url("nicht-mal-eine-url", :thumb) == "nicht-mal-eine-url"
      assert ImageVariant.url("/lokal/bild.png", :thumb) == "/lokal/bild.png"
    end
  end

  describe "Shopify" do
    test "hängt die Breite an" do
      assert ImageVariant.url("https://cdn.shopify.com/s/files/1/0/x.jpg", :thumb) ==
               "https://cdn.shopify.com/s/files/1/0/x.jpg?width=400"
    end

    test "ersetzt eine schon vorhandene Breite, statt eine zweite anzuhängen" do
      # Sonst stehen zwei width= in der Adresse und welches gilt, entscheidet
      # der Server — genau das, was wir hier festlegen wollen.
      ergebnis =
        ImageVariant.url("https://cdn.shopify.com/s/files/1/0/x.jpg?width=2048&v=17", :thumb)

      params = ergebnis |> URI.parse() |> Map.get(:query) |> URI.decode_query()

      assert params["width"] == "400"
      assert params["v"] == "17", "andere Parameter müssen erhalten bleiben"
      refute ergebnis =~ "width=2048"
    end

    test "der Vereinsshop von Union läuft ebenfalls auf Shopify" do
      assert ImageVariant.url(
               "https://fanartikel.union-zeughaus.de/cdn/shop/files/UB332600.webp",
               :thumb
             ) =~ "width=400"
    end

    test "medium ist größer als thumb" do
      klein = ImageVariant.url("https://cdn.shopify.com/s/files/1/0/x.jpg", :thumb)
      gross = ImageVariant.url("https://cdn.shopify.com/s/files/1/0/x.jpg", :medium)

      assert klein =~ "width=400"
      assert gross =~ "width=800"
    end
  end

  describe "Scayle" do
    test "setzt Breite und Qualität" do
      params =
        "https://bmg-live.cdn.scayle.cloud/images/25d0.jpg?quality=75"
        |> ImageVariant.url(:thumb)
        |> URI.parse()
        |> Map.get(:query)
        |> URI.decode_query()

      assert params == %{"width" => "400", "quality" => "75"}
    end
  end

  describe "Shopware-Vorschaubilder" do
    test "/media/ wird /thumbnail/ mit Größe im Dateinamen" do
      assert ImageVariant.url(
               "https://shop.mainz05.de/media/fb/f4/g0/1782808598/909819a2.jpeg",
               :thumb
             ) ==
               "https://shop.mainz05.de/thumbnail/fb/f4/g0/1782808598/909819a2_400x400.jpeg"
    end

    test "medium nimmt die größere Stufe" do
      assert ImageVariant.url("https://shop.mainz05.de/media/a/b.jpeg", :medium) =~ "_800x800."
    end

    test "ohne /media/ bleibt es, wie es ist" do
      url = "https://shop.mainz05.de/anders/b.jpeg"

      assert ImageVariant.url(url, :thumb) == url
    end

    test "Schalke läuft auf demselben Verfahren" do
      assert ImageVariant.url(
               "https://shop.schalke04.de/media/fe/93/12/1787119744/30501-adidas-Heimtrikot.png",
               :thumb
             ) ==
               "https://shop.schalke04.de/thumbnail/fe/93/12/1787119744/30501-adidas-Heimtrikot_400x400.png"
    end

    test "ein vorhandener Zeitstempel bleibt dran" do
      # Shopware hängt ?ts= an; fällt der weg, liefert der Shop unter Umständen
      # eine veraltete Fassung aus seinem Cache.
      assert ImageVariant.url("https://shop.schalke04.de/media/a/b.png?ts=1787119744", :thumb) =~
               "ts=1787119744"
    end

    test "ohne erkennbare Endung bleibt es, wie es ist" do
      url = "https://shop.mainz05.de/media/a/b"

      assert ImageVariant.url(url, :thumb) == url
    end
  end

  describe "Cloudinary" do
    test "die Umrechnung steht im Pfad, nicht im Parameter" do
      assert ImageVariant.url(
               "https://media.eintracht.de/image/upload/v1780936862/products/0110346_Trikot.jpg",
               :thumb
             ) ==
               "https://media.eintracht.de/image/upload/w_400/v1780936862/products/0110346_Trikot.jpg"
    end

    test "medium nimmt die größere Breite" do
      assert ImageVariant.url("https://media.eintracht.de/image/upload/v1/x.jpg", :medium) =~
               "/w_800/"
    end

    test "wird nur einmal eingesetzt" do
      # Ein zweites w_400 im Pfad wäre eine ungültige Transformationskette.
      ergebnis =
        ImageVariant.url("https://media.eintracht.de/image/upload/v1/image/upload/x.jpg", :thumb)

      assert length(String.split(ergebnis, "w_400")) == 2
    end

    test "ein anderer Pfad auf demselben Host bleibt unberührt" do
      url = "https://media.eintracht.de/anders/bild.jpg"

      assert ImageVariant.url(url, :thumb) == url
    end
  end

  describe "Leverkusen" do
    test "_L wird _M, nicht _S" do
      # _S ist 75x75 – in einer 230-px-Kachel sichtbar unscharf. Gemessen:
      # _S 4 kB / 75px, _M 20 kB / 480px, _L 68 kB / 992px.
      assert ImageVariant.url(
               "https://b04-ep-media-prod.azureedge.net/pickerimages-shop/2003830_Front1_902270_L.jpg",
               :thumb
             ) =~ "_902270_M.jpg"
    end

    test "greift nur am Ende der Adresse" do
      # Ein _L mitten im Dateinamen ist kein Größenkürzel.
      url = "https://b04-ep-media-prod.azureedge.net/x/TRIKOT_L_ANGE_ARM.jpg"

      assert ImageVariant.url(url, :thumb) == url
    end
  end

  describe "edge.storage" do
    test "die Stufe steckt im Pfad, nicht als Parameter" do
      assert ImageVariant.url(
               "https://4a2e5bfda6.edge.storage/res/product_450/adidas-Heimtrikot.jpg",
               :thumb
             ) == "https://4a2e5bfda6.edge.storage/res/product_200/adidas-Heimtrikot.jpg"
    end

    test "gilt für alle Zufallsnamen dieses CDNs" do
      # Jeder Shop bekommt dort einen eigenen Host – eine Positivliste wäre
      # nach dem nächsten Verein schon unvollständig.
      for host <- ["4a2e5bfda6", "72f3921709", "e591dcd21c"] do
        assert ImageVariant.url("https://#{host}.edge.storage/res/viewtwo_450/x.jpg", :thumb) =~
                 "viewtwo_200"
      end
    end

    test "ein anderer Pfad auf demselben Host bleibt unberührt" do
      url = "https://4a2e5bfda6.edge.storage/anders/bild.jpg"

      assert ImageVariant.url(url, :thumb) == url
    end
  end

  describe ":full" do
    test "lässt alles in Ruhe" do
      for url <- [
            "https://cdn.shopify.com/s/files/1/0/x.jpg",
            "https://shop.mainz05.de/media/a/b.jpeg",
            "https://4a2e5bfda6.edge.storage/res/product_450/x.jpg"
          ] do
        assert ImageVariant.url(url, :full) == url
      end
    end
  end

  test "nil bleibt nil" do
    for size <- ImageVariant.sizes() do
      assert ImageVariant.url(nil, size) == nil
    end
  end

  test "das Raster fordert thumb an" do
    # Die ganze Ersparnis hängt daran, dass die Kachel die kleine Stufe nimmt.
    # Ein Standardwert von :medium im Baustein macht die Regeln wirkungslos.
    quelle = File.read!("lib/kitrank_web/live/overview_live.ex")

    assert quelle =~ "size={:thumb}"
  end
end
