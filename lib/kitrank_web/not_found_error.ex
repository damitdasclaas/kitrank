defmodule KitrankWeb.NotFoundError do
  @moduledoc """
  Für Links, die es nicht (mehr) gibt: unbekannte Bearbeitungs-Tokens,
  Share-Slugs oder Raum-Codes.

  Führt zu einer 404 statt zu einem Serverfehler. Wichtig, weil diese Links der
  einzige Zugriffsweg sind – ein 500er würde verraten, dass an der Stelle
  überhaupt etwas sein könnte, und beim Raten helfen.
  """
  defexception [:message, plug_status: 404]
end
