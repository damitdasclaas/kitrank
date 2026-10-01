defmodule Mix.Tasks.Kitrank.BilderPruefen do
  @shortdoc "Prüft, ob verlinkte Bild- und Shop-Adressen noch erreichbar sind"

  @moduledoc """
  Ruft jede gespeicherte Bild- und Shop-Adresse ab und meldet, was nicht mehr
  antwortet.

      mix kitrank.bilder_pruefen

  Bilder werden nicht gehostet, nur verlinkt (siehe `Kitrank.Kits.Kit`) –
  ändert ein Verein seine Shop-Struktur oder nimmt ein Produkt offline, bricht
  der Link, ohne dass es hier jemand merkt, bis ein Besucher eine leere
  Kachel sieht. Dieser Befehl macht das vorher sichtbar, ändert aber nichts:
  Nachpflegen bleibt Handarbeit im Admin, am schnellsten über den Picker bei
  `cutout_url`.

  Meldungen mit HTTP 401/403/429 heißen nicht zwingend "tot" – manche Shops
  lehnen automatisierte Abrufe grundsätzlich ab und zeigen echten Besuchern
  trotzdem alles normal an. Ein 404 oder eine unbekannte Adresse dagegen schon.

  Auf dem Server:

      /app/bin/kitrank eval 'Kitrank.Release.bilder_pruefen()'
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    Kitrank.Kits.ImageCheck.run(log: fn text -> Mix.shell().info(text) end)
  end
end
