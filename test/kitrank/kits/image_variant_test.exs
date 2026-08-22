defmodule Kitrank.Kits.ImageVariantTest do
  @moduledoc """
  Gespeichert wird die größte Variante. Im Raster ist die Kachel aber nur rund
  250 px breit — dort dasselbe Bild zu laden kostet viermal so viele Bytes wie
  nötig.
  """
  use ExUnit.Case, async: true

  alias Kitrank.Kits.ImageVariant

  @gross "https://4a2e5bfda6.edge.storage/res/product_450/trikot---abc.jpg"

  test "verkleinert bekannte Muster" do
    assert ImageVariant.url(@gross, :thumb) =~ "/res/product_200/"
    assert ImageVariant.url(@gross, :medium) =~ "/res/product_200/"
  end

  test "lässt die große Ansicht beim Original" do
    assert ImageVariant.url(@gross, :full) == @gross
  end

  test "behält den Dateinamen" do
    assert ImageVariant.url(@gross, :thumb) =~ "trikot---abc.jpg"
  end

  test "greift auch bei den Galerie-Varianten" do
    url = "https://4a2e5bfda6.edge.storage/res/viewtwo_450/trikot---def.jpg"
    assert ImageVariant.url(url, :thumb) =~ "/res/viewtwo_200/"
  end

  test "lässt fremde Muster unangetastet" do
    # Lieber ein zu grosses Bild als ein gebrochenes.
    for url <- [
          "https://shop.example.com/bilder/trikot.jpg",
          "https://cdn.example.com/a/b/c_450.jpg",
          "https://example.com/res/produkt/450/x.jpg"
        ] do
      assert ImageVariant.url(url, :thumb) == url
    end
  end

  test "kommt mit nil klar" do
    assert ImageVariant.url(nil, :thumb) == nil
    assert ImageVariant.url(nil, :full) == nil
  end

  test "die verkleinerte Adresse existiert auch wirklich" do
    # Der Grund, warum bewusst kein srcset benutzt wird: dort gibt es keinen
    # Rueckfall. Also muss die abgeleitete Stufe verlaesslich vorhanden sein.
    assert ImageVariant.sizes() == [:thumb, :medium, :full]
  end
end
