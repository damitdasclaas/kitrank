defmodule Kitrank.Kits.ImageVariant do
  @moduledoc """
  Wählt zu einer gespeicherten Bild-URL die passende Größe für den Ort, an dem
  das Bild landet.

  Der Hintergrund: gespeichert wird die größte Variante, die der Shop hergibt —
  beim HSV 1000×1000 bei 108 KB. Im Raster ist die Kachel aber nur rund 250 px
  breit. Dort dasselbe Bild zu laden heißt, viermal so viele Bytes zu holen wie
  nötig; bei 36 Kacheln macht das 3,7 MB statt 0,9 MB.

  Einige Shop-CDNs kodieren die Größe im Pfad und liefern verlässlich alle
  Stufen. Für die erkennt diese Funktion die kleinere Variante. Alle anderen
  bekommen die Original-URL zurück — lieber ein zu großes Bild als ein
  gebrochenes.

  Bewusst kein `srcset`: dort gibt es keinen Rückfall, wenn eine abgeleitete
  Adresse nicht existiert. Ein einzelnes `src` mit bewusster Wahl ist hier das
  robustere Werkzeug.
  """

  @sizes [:thumb, :medium, :full]

  @doc "Die erlaubten Größen, von klein nach groß."
  def sizes, do: @sizes

  @doc """
  Passt die URL an die gewünschte Größe an, wenn das Muster bekannt ist.

    * `:thumb`  — Raster, Chips, Tabellen (~250 px)
    * `:medium` — Modale, Vergleichsspalten (~450 px)
    * `:full`   — große Ansicht (Original)
  """
  def url(nil, _size), do: nil
  def url(url, :full), do: url

  def url(url, size) when is_binary(url) and size in @sizes do
    # z. B. .../res/product_450/... und .../res/viewtwo_450/...
    case Regex.run(~r{^(.*/res/[a-z]+)_(\d+)(/.*)$}, url) do
      [_, prefix, _stufe, rest] -> prefix <> "_" <> edge_storage_step(size) <> rest
      _ -> url
    end
  end

  def url(url, _size), do: url

  # Die Stufen dieses CDNs sind keine Pixelwerte: _200 liefert 450 px, _450
  # liefert 1000 px.
  defp edge_storage_step(size) when size in [:thumb, :medium], do: "200"
end
