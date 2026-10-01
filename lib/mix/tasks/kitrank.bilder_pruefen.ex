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

  Die Ausgabe trennt deshalb zwei Töpfe: "wahrscheinlich tot" (404, unbekannte
  Adresse – ein eindeutiges Signal vom Shop) und "unklar" (blockiert, Timeout,
  nicht erreichbar – das sagt von einer Server-Adresse aus oft mehr über
  Bot-Abwehr als über den Link). Nur der erste Topf ist eine
  Handlungsaufforderung; der zweite kann zum großen Teil daraus bestehen, dass
  ein Shop Server-Anfragen grundsätzlich ablehnt und echten Besuchern trotzdem
  alles normal zeigt.

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
