defmodule Kitrank.Kits.ProductImages do
  @moduledoc """
  Holt zu einem Shop-Produktlink alle Bilder, die auf der Seite zu finden sind.

  Der Zweck ist ausdrücklich **nicht**, die Auswahl zu treffen. Welches Bild der
  Freisteller ist und welches eine Model-Aufnahme, entscheidet kein Skript
  zuverlässig — beim HSV war es je nach Produkt eine andere Position. Diese
  Funktion sammelt nur die Kandidaten ein, ausgewählt wird im Admin per Klick.

  Gearbeitet wird mit dem, was Shops von sich aus mitliefern:

    * `og:image` — praktisch überall vorhanden
    * JSON-LD `Product.image` — wo es das gibt, ist es die verlässlichste Quelle
    * `<img>` und `srcset` im Markup, gefiltert auf plausible Produktbilder

  Zusätzlich wird versucht, von einer kleinen Bildvariante auf die große zu
  schließen (`product_100` → `product_450`); das ist shopabhängig und wird nur
  übernommen, wenn die große Variante wirklich antwortet.

  Shops, die automatisierte Abrufe ablehnen, werden nicht umgangen: kommt eine
  Absage, sagt die Funktion das, und die URLs trägt man von Hand ein.
  """

  require Logger

  # Kurz genug, dass ein blockender Shop nicht wie ein Haenger wirkt.
  @timeout 12_000
  @max_bytes 3_000_000
  @max_images 40

  # Ein normaler Browser-User-Agent, damit Shops die Seite ausliefern wie an
  # jeden anderen Besucher auch. Kein Umgehen von Schutzmassnahmen: wer 403
  # sagt, bekommt keinen zweiten Versuch mit Tricks.
  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

  @doc """
  Sammelt Bildkandidaten zu einer Produktseite.

      {:ok, %{title: "adidas Heimtrikot 26/27", images: [...], source_url: "..."}}
      {:error, :blocked | :not_found | :unreachable | :invalid_url}
  """
  def fetch(url) when is_binary(url) do
    with {:ok, url} <- normalize(url),
         {:ok, body} <- get(url) do
      parse(body, url)
    end
  end

  def fetch(_), do: {:error, :invalid_url}

  # Fremdes HTML ist unberechenbar. Statt die aufrufende LiveView mitzureissen,
  # wird ein unerwarteter Fehler zu einer Meldung – und landet im Log, damit er
  # sich nachvollziehen laesst.
  defp parse(body, url) do
    try do
      kandidaten =
        []
        |> collect_json_ld(body)
        |> collect_open_graph(body)
        |> collect_markup(body, url)
        |> Enum.map(fn {u, label} -> {absolute(u, url), label} end)
        |> Enum.reject(fn {u, _} -> is_nil(u) end)
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.reject(fn {u, _} -> unwanted?(u) end)
        |> upgrade_variants()
        |> dedupe_by_file()
        |> Enum.take(@max_images)

      images = Enum.map(kandidaten, &elem(&1, 0))

      # Nur Beschreibungen behalten, die es wirklich gibt – ein leeres Label
      # waere in der Auswahl schlimmer als keines.
      labels =
        for {u, label} <- kandidaten,
            is_binary(label),
            String.trim(label) != "",
            into: %{},
            do: {u, String.trim(label)}

      cond do
        images != [] ->
          {:ok, %{title: title(body), images: images, labels: labels, source_url: url}}

        # Eine winzige Seite ohne Bilder ist fast immer eine JS-Huelle, die
        # ihren Inhalt erst im Browser nachlaedt.
        byte_size(body) < 50_000 ->
          {:error, :javascript}

        true ->
          {:error, :no_images}
      end
    rescue
      e ->
        Logger.warning("ProductImages: #{url} -> #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, :unparsable}
    end
  end

  defp normalize(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, String.trim(url)}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp get(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}, {"accept-language", "de-DE,de;q=0.9"}],
           receive_timeout: @timeout,
           max_redirects: 5,
           retry: false
         ) do
      {:ok, %{status: status, body: body}}
      when status in 200..299 and is_binary(body) and byte_size(body) <= @max_bytes ->
        {:ok, body}

      # Riesige Seiten schneiden wir ab, statt sie ganz zu verarbeiten.
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, binary_part(body, 0, @max_bytes)}

      {:ok, %{status: status}} when status in [401, 403, 429] ->
        {:error, :blocked}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        Logger.info("ProductImages: #{url} -> HTTP #{status}")
        {:error, {:status, status}}

      # Shops mit Bot-Schutz lassen die Verbindung oft einfach offen, statt
      # abzulehnen – das kommt hier als Timeout an.
      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: :nxdomain}} ->
        {:error, :unknown_host}

      {:error, exception} ->
        Logger.info("ProductImages: #{url} -> #{Exception.message(exception)}")
        {:error, :unreachable}
    end
  end

  ## Quellen

  defp collect_json_ld(acc, body) do
    ~r{<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>}s
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.flat_map(fn [json] ->
      case JSON.decode(String.trim(json)) do
        {:ok, data} -> product_images(data)
        _ -> []
      end
    end)
    |> then(&(acc ++ &1))
  end

  defp product_images(data) when is_list(data), do: Enum.flat_map(data, &product_images/1)

  defp product_images(%{"@type" => "Product", "image" => image}) do
    image |> List.wrap() |> Enum.map(&image_entry/1) |> Enum.reject(&is_nil/1)
  end

  defp product_images(%{"@graph" => graph}), do: product_images(graph)

  defp product_images(_), do: []

  # Manche Shops nennen die Bilder als reine Adressen, andere als ImageObject
  # mit Beschreibung. Die Beschreibung ist Gold wert: "Vorderansicht",
  # "Rueckansicht" – genau die Zuordnung, die man sonst per Auge trifft.
  defp image_entry(url) when is_binary(url), do: {url, nil}

  defp image_entry(%{} = obj) do
    case obj["url"] || obj["contentUrl"] || obj["image"] do
      url when is_binary(url) -> {url, obj["name"] || obj["caption"] || obj["description"]}
      _ -> nil
    end
  end

  defp image_entry(_), do: nil

  defp collect_open_graph(acc, body) do
    treffer =
      ~r{<meta[^>]+(?:property|name)="og:image(?::secure_url|:url)?"[^>]+content="([^"]+)"}i
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.map(fn [url] -> {unescape(url), nil} end)

    acc ++ treffer
  end

  defp collect_markup(acc, body, _url) do
    aus_src =
      ~r{<img[^>]+src="([^"]+\.(?:jpe?g|png|webp)[^"]*)"}i
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.map(fn [u] -> {unescape(u), nil} end)

    # srcset liefert oft die groesseren Varianten desselben Bildes.
    aus_srcset =
      ~r{srcset="([^"]+)"}i
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.flat_map(fn [set] ->
        set
        |> String.split(",")
        |> Enum.map(&(&1 |> String.trim() |> String.split(" ") |> List.first()))
      end)
      |> Enum.filter(&(&1 =~ ~r/\.(jpe?g|png|webp)/i))
      |> Enum.map(&{unescape(&1), nil})

    acc ++ aus_src ++ aus_srcset
  end

  defp title(body) do
    with nil <- match_one(~r{<meta[^>]+property="og:title"[^>]+content="([^"]+)"}i, body),
         nil <- match_one(~r{<title[^>]*>([^<]+)</title>}i, body) do
      nil
    else
      text -> text |> unescape() |> String.trim()
    end
  end

  # Shops kodieren in Attributen gern &amp;, &#47; und Konsorten.
  defp unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace(~r/&#(\d+);/, fn voll ->
      case Regex.run(~r/&#(\d+);/, voll, capture: :all_but_first) do
        [zahl] -> <<String.to_integer(zahl)::utf8>>
        _ -> voll
      end
    end)
  end

  defp match_one(regex, body) do
    case Regex.run(regex, body, capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end

  ## Aufräumen

  defp absolute(url, base) do
    url = String.trim(url)

    cond do
      url == "" -> nil
      String.starts_with?(url, "//") -> "#{URI.parse(base).scheme}:#{url}"
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "data:") -> nil
      true -> base |> URI.merge(url) |> URI.to_string()
    end
  end

  # Logos, Icons, Zahlungsarten und Platzhalter fliegen raus – sie machen die
  # Auswahl im Admin nur unuebersichtlich.
  @noise ~w(favicon sprite logo icon placeholder payment paypal klarna visa
            mastercard trustedshops siegel banner flag pixel spacer loading)

  defp unwanted?(url) do
    klein = String.downcase(url)
    Enum.any?(@noise, &String.contains?(klein, &1))
  end

  # Manche Shops kodieren die Bildgroesse im Pfad. Steht dort eine kleine
  # Variante, wird die grosse probiert – aber nur uebernommen, wenn es sie gibt.
  # Nebenlaeufig, nicht der Reihe nach: bei 40 Kandidaten summierten sich die
  # einzelnen Pruefungen auf ueber 40 Sekunden. Wer zu lange braucht, behaelt
  # einfach seine Original-Adresse.
  defp upgrade_variants(kandidaten) do
    kandidaten
    |> Task.async_stream(
      fn {url, label} ->
        case bigger(url) do
          nil -> {url, label}
          groesser -> if exists?(groesser), do: {groesser, label}, else: {url, label}
        end
      end,
      max_concurrency: 10,
      timeout: 5_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true
    )
    |> Enum.map(fn
      {:ok, ergebnis} -> ergebnis
      {:exit, {kandidat, _grund}} -> kandidat
    end)
    |> Enum.uniq_by(&elem(&1, 0))
  end

  # srcset liefert dasselbe Bild in fuenf Groessen. Fuer die Auswahl im Admin
  # zaehlt das Motiv, nicht die Aufloesung – also pro Dateiname nur einen
  # Treffer, und zwar den aus der vertrauenswuerdigsten Quelle (die stehen
  # vorne).
  defp dedupe_by_file(kandidaten) do
    kandidaten
    |> Enum.reduce({[], MapSet.new()}, fn {url, _label} = kandidat, {behalten, gesehen} ->
      name = url |> URI.parse() |> Map.get(:path, "") |> to_string() |> Path.basename()

      if name != "" and MapSet.member?(gesehen, name) do
        {behalten, gesehen}
      else
        {[kandidat | behalten], MapSet.put(gesehen, name)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp bigger(url) do
    cond do
      # z. B. .../res/product_100/... und .../res/viewtwo_50/...
      Regex.match?(~r{/res/[a-z]+_(?:50|100|200)/}, url) ->
        Regex.replace(~r{(/res/[a-z]+)_(?:50|100|200)/}, url, "\\1_450/")

      # Shopify skaliert ueber einen Parameter: ?width=1024
      Regex.match?(~r{[?&]width=\d+}, url) ->
        Regex.replace(~r{([?&]width=)\d+}, url, "\\g{1}2048")

      true ->
        nil
    end
  end

  defp exists?(url) do
    case Req.head(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 4_000,
           retry: false
         ) do
      {:ok, %{status: status}} -> status in 200..299
      _ -> false
    end
  end

  @doc """
  Fehlermeldung in Klartext – mit dem nächsten Schritt, nicht nur der Diagnose.

  Der Ausweg ist überall derselbe: Bild-URLs im Browser per Rechtsklick kopieren
  und unten von Hand einfügen. Deshalb steht er dabei, wo er hilft.
  """
  def message(:timeout),
    do:
      "Der Shop hat nicht geantwortet. Viele Shops blocken automatisierte Abrufe still — " <>
        "kopier die Bild-Adressen im Browser per Rechtsklick und füg sie unten ein."

  def message(:blocked),
    do:
      "Dieser Shop lässt automatisierte Abrufe nicht zu. Bild-Adressen im Browser " <>
        "per Rechtsklick kopieren und unten einfügen."

  def message(:javascript),
    do:
      "Diese Seite lädt ihre Bilder erst im Browser nach, der Server sieht sie nicht. " <>
        "Bild-Adressen per Rechtsklick kopieren und unten einfügen."

  def message(:no_images), do: "Auf der Seite waren keine Bilder zu finden."
  def message(:not_found), do: "Die Seite gibt es nicht (404). Stimmt der Link?"
  def message(:unknown_host), do: "Diese Adresse gibt es nicht. Vertippt?"

  def message({:status, status}), do: "Der Shop hat mit HTTP #{status} geantwortet."

  def message(:unparsable),
    do: "Die Seite ließ sich nicht auswerten. Bild-Adressen bitte von Hand einfügen."

  def message(:invalid_url), do: "Das sieht nicht nach einer Adresse aus (http:// oder https://)."

  def message(:unreachable),
    do: "Die Seite war nicht erreichbar. Bild-Adressen kannst du auch von Hand einfügen."
end
