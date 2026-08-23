defmodule Kitrank.Kits.Thumbs do
  @moduledoc """
  Trägt die kleinen Bildvarianten für bestehende Trikots nach.

  Der Picker macht das beim Auswählen automatisch. Diese Funktion ist für die
  Trikots, die es vorher schon gab — `source_shop_url` ist gespeichert, also
  lässt sich die Produktseite erneut lesen, ohne dass jemand etwas eintippt.
  """
  import Ecto.Query

  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias Kitrank.Repo

  @images Application.compile_env(:kitrank, :product_images, Kits.ProductImages)

  @doc """
  Läuft über alle Trikots mit Shop-Link und Freisteller.

  Ohne `write: true` wird nur berichtet — bei Abrufen auf fremden Seiten ist ein
  Probelauf die Höflichkeit gegenüber dem eigenen Datenbestand.
  """
  def run(opts \\ []) do
    schreiben? = Keyword.get(opts, :write, false)
    sag = Keyword.get(opts, :log, &IO.puts/1)

    kits =
      Repo.all(
        from k in Kit,
          where: not is_nil(k.source_shop_url) and not is_nil(k.cutout_url),
          preload: [:team]
      )

    sag.("#{length(kits)} Trikots mit Shop-Link#{if schreiben?, do: "", else: " (Probelauf)"}")

    ergebnisse =
      kits
      |> Task.async_stream(&pruefe/1, max_concurrency: 6, timeout: 60_000, on_timeout: :kill_task)
      |> Enum.map(fn
        {:ok, ergebnis} -> ergebnis
        {:exit, _} -> {:fehler, nil, :timeout}
      end)

    for {status, kit, wert} <- ergebnisse do
      case status do
        :gefunden ->
          sag.("  gefunden  #{kit.team.short_code} #{kit.kit_type}: #{kuerze(wert)}")
          if schreiben?, do: schreibe(kit, wert)

        :unveraendert ->
          sag.("  —         #{kit.team.short_code} #{kit.kit_type}: keine kleinere Variante")

        :fehler ->
          name = if kit, do: "#{kit.team.short_code} #{kit.kit_type}", else: "?"
          sag.("  Fehler    #{name}: #{inspect(wert)}")
      end
    end

    zahl = Enum.count(ergebnisse, &(elem(&1, 0) == :gefunden))
    sag.("#{zahl} Varianten #{if schreiben?, do: "eingetragen", else: "gefunden"}")
    zahl
  end

  defp pruefe(kit) do
    case @images.fetch(kit.source_shop_url) do
      {:ok, ergebnis} ->
        karte = Map.get(ergebnis, :variants, %{})

        treffer =
          Map.get(karte, kit.cutout_url) ||
            Map.get(karte, {:motiv, Kits.ProductImages.motiv(kit.cutout_url)})

        if treffer && treffer != kit.cutout_url do
          {:gefunden, kit, treffer}
        else
          {:unveraendert, kit, nil}
        end

      {:error, grund} ->
        {:fehler, kit, grund}
    end
  end

  defp schreibe(kit, url) do
    kit
    |> Kit.changeset(%{"cutout_thumb_url" => url})
    |> Repo.update()
  end

  defp kuerze(url) when is_binary(url) do
    if String.length(url) > 70, do: String.slice(url, 0, 70) <> "…", else: url
  end
end
