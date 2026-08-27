defmodule Mix.Tasks.Kitrank.Aufraeumen do
  @shortdoc "Meldet und löscht Trikots, deren Kategorie ihre Sportart nicht kennt"

  @moduledoc """
  Trikots, die zu einer Kategorie gehören, die ihre Sportart abgelegt hat.

      mix kitrank.aufraeumen              # nur melden
      mix kitrank.aufraeumen --loeschen   # wirklich löschen

  Der Fall, für den es gebaut wurde: die NFL hatte 32 Ausweichtrikots, weil
  der Import diese Kategorie anfangs für alle Sportarten gleich anlegte.

  Gelöscht wird nur, was wirklich niemand braucht — kein Bild, kein Shop-Link,
  kein Name, und in keiner Rangliste. Alles andere wird gemeldet und
  angefasst: der Fremdschlüssel steht auf `delete_all`, ein Trikot mit
  Einträgen zu löschen würde es still aus fremden Ranglisten entfernen.

  Auf dem Server:

      /app/bin/kitrank eval 'Kitrank.Release.aufraeumen()'
      /app/bin/kitrank eval 'Kitrank.Release.aufraeumen(loeschen: true)'
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    loeschen? = "--loeschen" in args
    Mix.shell().info(Kitrank.Kits.aufraeum_bericht(loeschen: loeschen?))
  end
end
