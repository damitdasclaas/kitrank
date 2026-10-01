defmodule Mix.Tasks.Kitrank.BilderPruefen do
  @shortdoc "Prüft, ob Bild-Adressen und Vereinsshop-Links noch erreichbar sind"

  @moduledoc """
  Ruft die Bild-Adressen jedes Trikots und den Vereinsshop-Link jedes Teams
  ab und meldet, was nicht mehr antwortet.

      mix kitrank.bilder_pruefen

  Geprüft wird nur, was öffentlich auch gezeigt wird: `cutout_url`,
  `cutout_thumb_url`, `model_image_urls` am Trikot und `shop_url` am Team.
  `Kit.source_shop_url` fehlt bewusst – der ist seit der Entfernung der
  Pro-Trikot-Shop-Links nur noch eine interne Quelle für den Bilder-Picker,
  kein öffentlicher Link mehr.

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
