defmodule Kitrank.Kits.ImageVariant do
  @moduledoc """
  Wählt zu einer gespeicherten Bild-URL die passende Größe für den Ort, an dem
  das Bild landet.

  Der Hintergrund: gespeichert wird die größte Variante, die der Shop hergibt —
  bei Mainz 1200×1200 bei 321 KB. Im Raster ist die Kachel aber nur rund 230 px
  breit. Dort dasselbe Bild zu laden heißt, das Fünfzehnfache der nötigen Bytes
  zu holen.

  ## Zwei Wege, und nur einer kennt Shops

  **Der erste Weg braucht kein Host-Wissen.** Ein `srcset`-Attribut zaehlt per
  Definition die Varianten *eines* Bildes auf. `Kitrank.Kits.ProductImages`
  liest das beim Einlesen mit und merkt sich die kleinste brauchbare Adresse in
  `cutout_thumb_url`. Das funktioniert bei jedem Shop, der sich an den Standard
  haelt — gemessen bei 8 von 11 erreichbaren Vereinsshops, und es kann keine
  Adresse erfinden, weil ausschliesslich benutzt wird, was der Shop selbst
  ausgeliefert hat. `for_kit/3` bevorzugt diesen Weg.

  **Der zweite Weg sind die Regeln unten.** Sie greifen dort, wo eine Seite
  kein `srcset` veroeffentlicht (HSV, Eintracht, Augsburg). Diese Liste soll
  nicht mehr wachsen: ein neuer Verein oder eine neue Sportart wird ueber den
  ersten Weg abgedeckt, ohne dass jemand etwas vermisst.

  ## Warum eine Positivliste und keine Heuristik

  Die Größenangabe sieht bei vielen Shop-CDNs gleich aus (`?width=400`), aber
  was der Server damit macht, ist nicht geraten, sondern gemessen — und der
  Unterschied ist erheblich:

      Shop            Original      mit ?width=400
      Mainz (Shopware)   321 kB   →     17 kB   (1200² → 400²)
      Gladbach (Scayle)  145 kB   →     22 kB
      VfB                 86 kB   →     12 kB
      Union (Shopify)     64 kB   →     22 kB
      Köln (Shopify)      37 kB   →     16 kB
      Leverkusen  _L→_M   68 kB   →     20 kB   (992² → 480²)
      Schalke /thumbnail/ 339 kB   →    154 kB   (400²)
      Eintracht (Cloudinary) 145 kB →    24 kB   (1500² → 400², Pfad w_400)
      Schalke ?width=400  339 kB   →   2520 kB   ← Parameter ignoriert,
                                                  liefert PNG statt AVIF

  Schalke ist der Grund für diese Liste. Ein Shop, der die Angabe nicht kennt,
  kann sie ignorieren (harmlos), mit 404 antworten (Bild kaputt) oder auf eine
  ganz andere Repräsentation umschalten (siebenmal so groß). Deshalb bekommt nur
  ein gemessener Host eine Regel; alle anderen die Original-URL.

  **Gemessen und bewusst ausgelassen:** `prod-api.tsg-hoffenheim.de` (die Größe
  steht im Dateinamen, wird aber ignoriert — der `?context=`-Parameter ist eine
  signierte Pfadkodierung), `cdn11.bigcommerce.com`, `assets.redbullshop.com` —
  dort ändert keine der geprüften Angaben etwas.

  Nachzumessen mit `mix run priv/scripts/bildgroessen_pruefen.exs`.

  Bewusst kein `srcset`: dort gibt es keinen Rückfall, wenn eine abgeleitete
  Adresse nicht existiert. Ein einzelnes `src` plus der Rückfall im Browser
  (siehe `KitrankWeb.KitComponents.kit_figure/1`) ist hier das robustere
  Werkzeug.
  """

  @sizes [:thumb, :medium, :full]

  # Zielbreiten. Die Kachel im Raster ist bei 1500 px Gesamtbreite und sechs
  # Spalten rund 230 px breit — 400 px deckt damit auch Bildschirme mit
  # doppelter Pixeldichte ab.
  @breite %{thumb: 400, medium: 800}

  @doc "Die erlaubten Größen, von klein nach groß."
  def sizes, do: @sizes

  @doc """
  Wie `url/2`, bevorzugt aber die im Trikot gespeicherte kleine Adresse.

  Drei Stufen, jede mit Rückfall: die Variante, die der Shop selbst
  ausgeliefert hat — sonst eine Regel, wenn der Host bekannt ist — sonst das
  Original. Die erste Stufe braucht es dort, wo die Größe nicht in der Adresse
  steht, sondern in einem signierten Token (TSG: 304 kB gegen 18 kB, und aus
  der großen Adresse ist die kleine nicht errechenbar).

  Gilt nur für den Freisteller: nur der landet im Raster.
  """
  def for_kit(kit, url, size)

  def for_kit(%{cutout_thumb_url: thumb, cutout_url: cutout}, url, size)
      when is_binary(thumb) and thumb != "" and size in [:thumb, :medium] and url == cutout do
    thumb
  end

  def for_kit(_kit, url, size), do: url(url, size)

  @doc """
  Passt die URL an die gewünschte Größe an, wenn der Host bekannt ist.

    * `:thumb`  — Raster, Chips, Tabellen (400 px)
    * `:medium` — Modale, Vergleichsspalten (800 px)
    * `:full`   — große Ansicht (Original)

      iex> url("https://cdn.shopify.com/s/files/1/1/x.jpg", :thumb)
      "https://cdn.shopify.com/s/files/1/1/x.jpg?width=400"

      iex> url("https://beispiel.de/bild.jpg", :thumb)
      "https://beispiel.de/bild.jpg"

      iex> url(nil, :thumb)
      nil
  """
  def url(nil, _size), do: nil
  def url(url, :full), do: url

  def url(url, size) when is_binary(url) and size in @sizes do
    breite = @breite[size]

    case URI.parse(url) do
      %URI{host: host} = uri when is_binary(host) -> regel(host, uri, url, size, breite)
      _ -> url
    end
  end

  def url(url, _size), do: url

  ## Die Regeln, eine je gemessener Host-Familie

  # Shopify hängt die Breite als Parameter an und liefert genau diese Kantenlänge.
  defp regel("cdn.shopify.com", uri, _url, _size, breite), do: mit_param(uri, "width", breite)

  defp regel("fanartikel.union-zeughaus.de", uri, _url, _size, breite),
    do: mit_param(uri, "width", breite)

  # Scayle braucht die Qualität dazu, sonst bleibt es beim Original.
  defp regel("bmg-live.cdn.scayle.cloud", uri, _url, _size, breite) do
    uri |> mit_params(%{"width" => breite, "quality" => 75})
  end

  defp regel("assets.vfb.de", uri, _url, _size, breite), do: mit_param(uri, "width", breite)

  # Shopware legt Vorschaubilder unter /thumbnail/ ab, mit der Größe im
  # Dateinamen. Existiert die Stufe nicht, gibt es 404 — dafür ist der Rückfall
  # im Browser da.
  #
  # Schalke ist hier der lehrreiche Fall: derselbe Shop liefert auf `?width=400`
  # das Siebenfache (2520 kB PNG statt 339 kB AVIF), auf `/thumbnail/` aber
  # brav 154 kB. Eine Regel gilt nie für einen Host, sondern immer für ein
  # Host-und-Verfahren-Paar.
  defp regel(host, %URI{path: pfad} = uri, url, _size, breite)
       when host in ["shop.mainz05.de", "shop.schalke04.de"] and is_binary(pfad) do
    with true <- String.starts_with?(pfad, "/media/"),
         [_, ohne_endung, endung] <- Regex.run(~r/^(.*)\.([a-z]{3,4})$/i, pfad) do
      neu = String.replace_prefix(ohne_endung, "/media/", "/thumbnail/")
      URI.to_string(%{uri | path: "#{neu}_#{breite}x#{breite}.#{endung}"})
    else
      _ -> url
    end
  end

  # Cloudinary nimmt die Umrechnung im Pfad, nicht als Parameter: aus
  # /image/upload/v123/… wird /image/upload/w_400/v123/…. Gemessen brachte das
  # blanke w_400 (24 kB) mehr als w_400,f_auto,q_auto (33 kB) — q_auto hält die
  # Qualität höher, als die Kachel braucht.
  defp regel("media.eintracht.de", %URI{path: pfad} = uri, url, _size, breite)
       when is_binary(pfad) do
    if String.contains?(pfad, "/image/upload/") do
      neu = String.replace(pfad, "/image/upload/", "/image/upload/w_#{breite}/", global: false)
      URI.to_string(%{uri | path: neu})
    else
      url
    end
  end

  # Leverkusen benennt die Stufen _S (75 px), _M (480 px), _L (992 px).
  # _S ist für eine 230-px-Kachel zu klein und sichtbar unscharf.
  defp regel("b04-ep-media-prod.azureedge.net", _uri, url, _size, _breite) do
    String.replace(url, ~r/_L\.(jpe?g|png|webp)$/i, "_M.\\1")
  end

  # Dieses CDN kodiert die Stufe im Pfad, und zwar nicht in Pixeln: _200 liefert
  # 450 px, _450 liefert 1000 px. Regel über die Pfadform, weil die Hosts
  # wechselnde Zufallsnamen haben (4a2e5bfda6.edge.storage, 72f3921709…).
  defp regel(host, _uri, url, _size, _breite) do
    if String.ends_with?(host, ".edge.storage") or host == "edge.storage" do
      case Regex.run(~r{^(.*/res/[a-z]+)_(\d+)(/.*)$}, url) do
        [_, prefix, _stufe, rest] -> prefix <> "_200" <> rest
        _ -> url
      end
    else
      url
    end
  end

  ## Hilfe

  # Setzt einen Parameter und ersetzt ihn, falls er schon da ist — sonst stehen
  # zwei width= in der Adresse und welches gilt, entscheidet der Server.
  defp mit_param(%URI{} = uri, name, wert), do: mit_params(uri, %{name => wert})

  defp mit_params(%URI{} = uri, paare) do
    neu = Map.new(paare, fn {k, v} -> {k, to_string(v)} end)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.merge(neu)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end
end
