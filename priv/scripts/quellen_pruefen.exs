# Prueft, welche Vereinsshops ihre Trikots in der Sitemap fuehren.
#
#     mix run priv/scripts/quellen_pruefen.exs
#
# Warum ein Skript und kein Test: es geht ins Netz, das Ergebnis haengt an
# fremden Servern und aendert sich, sobald ein Shop umbaut. Ein Test, der davon
# rot wird, sagt nichts ueber diesen Code. Der Stand vom 23.08.2026 steht in
# roadmap.md Abschnitt 3.1b — dieses Skript ist der Weg, ihn nachzuziehen.
#
# Bot-Schutz wird respektiert: normaler Browser-UA, keine Wiederholung nach
# einem 403, kein Umgehen von Cloudflare-Pruefungen.

trikot = ~r/trikot|jersey|maillot/i

ua =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"

hol = fn url ->
  # try/rescue statt eines rescue am Funktionsende: eine anonyme Funktion hat
  # keinen impliziten Rumpf, an den sich rescue haengen koennte.
  try do
    case Req.get(url,
           headers: [{"user-agent", ua}, {"accept-language", "de-DE,de;q=0.9"}],
           receive_timeout: 30_000,
           retry: false,
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} when byte_size(body) > 0 ->
        # .gz-Sitemaps kommen als gzip-Inhalt, nicht als gzip-Transport – die
        # Endung reicht nicht, deshalb die Signatur.
        if binary_part(body, 0, 2) == <<0x1F, 0x8B>> do
          {:ok, :zlib.gunzip(body)}
        else
          {:ok, body}
        end

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, grund} ->
        {:error, grund}
    end
  rescue
    e -> {:error, e.__struct__}
  end
end

locs = fn body ->
  ~r{<loc>\s*([^<\s]+)\s*</loc>}
  |> Regex.scan(body)
  |> Enum.map(&Enum.at(&1, 1))
end

# Sitemaps sind oft geschachtelt – bei RB Leipzig drei Ebenen: Index je
# Sprache, darin ein Index je Bereich, erst darunter die Seiten. Deshalb
# rekursiv mit Tiefenbegrenzung, nicht mit einem festen Abstieg.
sammle = fn sammle, url, tiefe ->
  case hol.(url) do
    {:ok, body} ->
      alle = locs.(body)

      if String.contains?(body, "<sitemapindex") and tiefe > 0 do
        alle
        |> Enum.take(8)
        |> Enum.flat_map(&sammle.(sammle, &1, tiefe - 1))
      else
        alle
      end

    {:error, _} ->
      []
  end
end

pruefe = fn url ->
  case hol.(url) do
    {:ok, _} ->
      alle = sammle.(sammle, url, 3)
      {:ok, alle, Enum.filter(alle, &Regex.match?(trikot, &1))}

    {:error, grund} ->
      {:error, grund}
  end
end

# Liegt die Sitemap nicht am Standardort, steht ihr Pfad in robots.txt. Ohne
# diesen Rueckfall melden SGE, FCE und RBL faelschlich "nichts gefunden".
aus_robots = fn basis ->
  case hol.(basis <> "/robots.txt") do
    {:ok, txt} ->
      ~r/(?im)^\s*sitemap:\s*(\S+)/
      |> Regex.scan(txt)
      |> Enum.map(&Enum.at(&1, 1))

    _ ->
      []
  end
end

Kitrank.Kits.list_teams()
|> Enum.reject(&(is_nil(&1.shop_url) or &1.shop_url == ""))
|> Enum.map(fn team ->
  %URI{scheme: schema, host: host} = URI.parse(team.shop_url)
  {team.short_code, "#{schema}://#{host}"}
end)
# Zehn Vereine liegen auf derselben Plattform – einmal fragen genuegt.
|> Enum.uniq_by(fn {_, basis} -> basis end)
|> Task.async_stream(
  fn {code, basis} ->
    ergebnis =
      case pruefe.(basis <> "/sitemap.xml") do
        {:ok, _, treffer} = gut when treffer != [] ->
          gut

        schwach ->
          basis
          |> aus_robots.()
          |> Enum.find_value(schwach, fn url ->
            case pruefe.(url) do
              {:ok, _, treffer} = gut when treffer != [] -> gut
              _ -> nil
            end
          end)
      end

    {code, ergebnis}
  end,
  max_concurrency: 6,
  timeout: 150_000,
  on_timeout: :kill_task
)
|> Enum.each(fn
  {:ok, {code, {:ok, alle, treffer}}} ->
    marke = if length(treffer) >= 2, do: "JA ", else: "—  "

    IO.puts(
      "#{marke} #{String.pad_trailing(code, 5)} URLs=#{length(alle)} Trikot=#{length(treffer)}"
    )

    treffer |> Enum.take(2) |> Enum.each(&IO.puts("        #{&1}"))

  {:ok, {code, {:error, grund}}} ->
    IO.puts("—   #{String.pad_trailing(code, 5)} #{inspect(grund)}")

  {:exit, grund} ->
    IO.puts("—   abgebrochen: #{inspect(grund)}")
end)
