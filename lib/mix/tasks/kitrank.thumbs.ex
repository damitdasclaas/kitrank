defmodule Mix.Tasks.Kitrank.Thumbs do
  @shortdoc "Holt die kleinen Bildvarianten für bestehende Trikots nach"

  @moduledoc """
  Ruft für jedes Trikot mit Shop-Link die Produktseite ab und merkt sich die
  kleine Variante des Freistellers, sofern der Shop eine anbietet.

      mix kitrank.thumbs          # nur zeigen, was passieren würde
      mix kitrank.thumbs --write  # eintragen

  Warum nicht automatisch im Hintergrund: das sind Abrufe bei fremden Shops,
  und die gehören nicht in einen Seitenaufruf. Einmal nach einer Datenpflege
  laufen lassen genügt.

  In Produktion über die Freigabe:

      /app/bin/kitrank eval "Kitrank.Release.thumbs(write: true)"
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Kitrank.Kits.Thumbs.run(write: "--write" in args, log: fn text -> Mix.shell().info(text) end)
  end
end
