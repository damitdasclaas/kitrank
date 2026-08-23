# Misst, was die Größenregeln aus Kitrank.Kits.ImageVariant wirklich einsparen.
#
#     mix run priv/scripts/bildgroessen_pruefen.exs
#
# Warum ein Skript und kein Test: es lädt Bilder von fremden CDNs. Ein Test,
# der rot wird, weil ein Shop sein CDN wechselt, sagt nichts über diesen Code —
# und die Regeln selbst sind in test/kitrank/image_variant_test.exs geprüft.
#
# Was hier auffällt, gehört in die Tabelle im Moduldoc von ImageVariant. Wird
# eine Zeile *größer*, muss die Regel raus: bei Schalke liefert ?width=400
# statt 339 kB AVIF ganze 2520 kB PNG.

import Ecto.Query

alias Kitrank.Kits.ImageVariant

ua =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"

hol = fn url ->
  try do
    case Req.get(url,
           headers: [{"user-agent", ua}, {"accept", "image/avif,image/webp,*/*"}],
           receive_timeout: 20_000,
           retry: false,
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, byte_size(body)}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, grund} -> {:error, inspect(grund.__struct__)}
    end
  rescue
    e -> {:error, inspect(e.__struct__)}
  end
end

Kitrank.Repo.all(
  from k in Kitrank.Kits.Kit,
    where: not is_nil(k.cutout_url),
    select: k.cutout_url,
    distinct: true
)
|> Enum.map(&{&1, ImageVariant.url(&1, :thumb)})
|> Task.async_stream(
  fn {original, klein} ->
    {original, klein, hol.(original), if(klein == original, do: :gleich, else: hol.(klein))}
  end,
  max_concurrency: 8,
  timeout: 60_000,
  on_timeout: :kill_task
)
|> Enum.each(fn
  {:ok, {original, _klein, {:ok, gross}, :gleich}} ->
    IO.puts(
      "  —   #{String.pad_leading("#{div(gross, 1024)}", 5)} kB  keine Regel  #{URI.parse(original).host}"
    )

  {:ok, {original, _klein, {:ok, gross}, {:ok, klein}}} ->
    marke = if klein < gross, do: " ok ", else: "!! GRÖSSER"
    prozent = if gross > 0, do: 100 - div(klein * 100, gross), else: 0

    IO.puts(
      "  #{marke} #{String.pad_leading("#{div(gross, 1024)}", 5)} kB → " <>
        "#{String.pad_leading("#{div(klein, 1024)}", 5)} kB  (#{prozent}%)  #{URI.parse(original).host}"
    )

  {:ok, {original, _klein, {:ok, gross}, {:error, grund}}} ->
    # Ein Fehler auf der abgeleiteten Adresse heisst: der Rückfall im Browser
    # springt ein. Es funktioniert, kostet aber einen zusätzlichen Umlauf.
    IO.puts(
      "  !!  #{String.pad_leading("#{div(gross, 1024)}", 5)} kB → #{grund} auf der kleinen Variante  #{URI.parse(original).host}"
    )

  {:ok, {original, _klein, {:error, grund}, _}} ->
    IO.puts("  ??  Original nicht erreichbar (#{grund})  #{URI.parse(original).host}")

  {:exit, _} ->
    IO.puts("  ??  Zeitüberschreitung")
end)
