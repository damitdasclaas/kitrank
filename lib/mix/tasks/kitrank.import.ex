defmodule Mix.Tasks.Kitrank.Import do
  @shortdoc "Spielt die Stammdaten einer Saison ein"

  @moduledoc """
  Vereine, Ligen und Saison-Zuordnungen aus einer Datei einspielen.

      mix kitrank.import                              # priv/data/teams_2026_27.json
      mix kitrank.import priv/data/nfl_2026_27.json   # die NFL
      mix kitrank.import priv/data/eigene.json        # eine andere Datei

  Jede Datei beschreibt eine Sportart und räumt nur in ihrer eigenen auf — die
  Läufe stören sich also nicht gegenseitig.

  Idempotent — mehrfaches Ausführen ändert nichts doppelt.

  Auf dem Server:

      /app/bin/kitrank eval 'Kitrank.Release.import_teams()'
  """
  use Mix.Task

  alias Kitrank.Kits.Import

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    case Import.run(List.first(args)) do
      {:ok, bericht} -> Mix.shell().info("\n" <> Import.format(bericht))
      {:error, grund} -> Mix.raise(to_string(grund))
    end
  end
end
