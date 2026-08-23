defmodule Kitrank.ProductVariantsTest do
  @moduledoc """
  Die Zuordnung „großes Bild → kleine Variante desselben Bildes".

  Der Punkt daran ist, dass sie **keinen Shop kennt**. Ein `srcset`-Attribut
  zählt per Definition die Varianten eines Bildes auf; damit funktioniert das
  bei jedem Shop, der sich an den Standard hält, und nicht nur bei denen, deren
  Adressen wir vermessen haben.

  Wichtiger noch: dieser Weg kann keine Adresse erfinden. Bei Schalke liefert
  ein geratenes `?width=400` das Siebenfache (2520 kB PNG statt 339 kB AVIF) —
  hier wird ausschließlich benutzt, was der Shop selbst ausgeliefert hat, also
  ist diese Klasse von Fehler bauartbedingt ausgeschlossen.
  """
  use ExUnit.Case, async: true

  alias Kitrank.Kits.ProductImages

  # Der Abruf ist privat; geprüft wird über fetch/1 mit einer echten
  # Seite ist hier nicht möglich, also über die öffentliche motiv/1 und über
  # den Picker-Test. Was hier bleibt, ist die Motiv-Erkennung — der Teil, der
  # entscheidet, ob eine Variante zum gewählten Bild gehört.
  describe "motiv/1 erkennt dasselbe Bild in verschiedenen Größen" do
    test "Shopify hängt die Größe als Parameter an" do
      assert ProductImages.motiv("https://cdn.shopify.com/s/files/x.jpg?v=1&width=2048") ==
               ProductImages.motiv("https://cdn.shopify.com/s/files/x.jpg?v=1&width=352")
    end

    test "Shopware legt die kleine Stufe unter /thumbnail/ ab" do
      assert ProductImages.motiv("https://shop.mainz05.de/media/a/b/c.jpeg") ==
               ProductImages.motiv("https://shop.mainz05.de/thumbnail/a/b/c_400x400.jpeg")
    end

    test "manche Shops schreiben die Maße in den Dateinamen" do
      assert ProductImages.motiv("https://x.de/medias/1200Wx1200H-103333-Trikot") ==
               ProductImages.motiv("https://x.de/medias/515Wx515H-103333-Trikot")
    end

    test "und manche in den Pfad" do
      assert ProductImages.motiv("https://x.edge.storage/res/product_450/a.jpg") ==
               ProductImages.motiv("https://x.edge.storage/res/product_200/a.jpg")
    end

    test "Stufenkürzel am Ende zählen auch" do
      assert ProductImages.motiv("https://x.de/bild_L.jpg") ==
               ProductImages.motiv("https://x.de/bild_M.jpg")
    end

    test "zwei verschiedene Bilder bleiben verschieden" do
      # Ohne das würde die Zuordnung ein fremdes Motiv als Vorschaubild
      # einsetzen – schlimmer als ein zu großes Bild.
      refute ProductImages.motiv("https://x.de/heimtrikot.jpg") ==
               ProductImages.motiv("https://x.de/auswaertstrikot.jpg")
    end

    test "der Parameter allein macht kein neues Motiv, der Dateiname schon" do
      refute ProductImages.motiv("https://cdn.shopify.com/s/a.jpg?width=400") ==
               ProductImages.motiv("https://cdn.shopify.com/s/b.jpg?width=400")
    end
  end

  describe "fetch/1 auf einer echten srcset-Struktur" do
    @tag :external
    test "TSG: die 515er wird der 1200er zugeordnet" do
      # Der Fall, für den es den ganzen Mechanismus gibt: die Größe steckt in
      # einem signierten ?context=-Token, aus der großen Adresse ist die kleine
      # nicht errechenbar. 304 kB gegen 18 kB.
      #
      # Als :external markiert – der Test geht ins Netz und gehört nicht in
      # den Standardlauf.
      {:ok, ergebnis} =
        ProductImages.fetch("https://shop.tsg-hoffenheim.de/de/p/000000000000103333")

      gross = hd(ergebnis.images)

      klein =
        Map.get(ergebnis.variants, gross) ||
          Map.get(ergebnis.variants, {:motiv, ProductImages.motiv(gross)})

      assert klein
      assert klein =~ "515Wx515H"
      assert gross =~ "1200Wx1200H"
    end
  end
end
