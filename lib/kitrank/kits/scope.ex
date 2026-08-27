defmodule Kitrank.Kits.Scope do
  @moduledoc """
  Welche Trikots gemeint sind — über vier Achsen: Saisons, Ligen, Vereine,
  Trikot-Typen.

  **Jede leere Liste heißt „keine Einschränkung".** `%Scope{}` ist damit
  schlicht „alles, was es gibt". Das ist die Regel, an der sich alle vier
  Achsen halten, und sie erspart jedem Aufrufer den Sonderfall.

  Es gab den Begriff vorher zweimal: `Kits.list_kits_for_scope/1` nahm eine
  Map mit `seasons` (Mehrzahl) und `team_ids`, das Reveal führte `season`
  (Einzahl) und `kit_types` als Spalten und hatte eine eigene Abfrage dafür.
  Zwei Fassungen desselben Gedankens laufen auseinander — an der fehlenden
  Trikot-Typ-Achse war es schon passiert: „alle Auswärtstrikots dieser vier
  Vereine" ließ sich als Rangliste gar nicht ausdrücken.

  Nicht zu verwechseln mit `Kitrank.Accounts.Scope`: das ist die angemeldete
  Person, das hier ein Ausschnitt des Trikot-Bestands.
  """

  defstruct seasons: [], competition_ids: [], team_ids: [], kit_types: []

  @type t :: %__MODULE__{
          seasons: [String.t()],
          competition_ids: [integer()],
          team_ids: [integer()],
          kit_types: [String.t()]
        }

  @doc """
  Baut einen Ausschnitt aus allem, was danach aussieht — Struct, Map mit
  Atom- oder String-Schlüsseln, `nil`.

  Fehlende Achsen bleiben leer, also unbeschränkt. Unbekannte Schlüssel fallen
  weg: der Ausschnitt kommt teils aus Formularen, und was er nicht kennt, soll
  er nicht durchreichen.
  """
  def new(%__MODULE__{} = scope), do: scope
  def new(nil), do: %__MODULE__{}

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      seasons: liste(attrs, :seasons),
      competition_ids: liste(attrs, :competition_ids),
      team_ids: liste(attrs, :team_ids),
      kit_types: liste(attrs, :kit_types)
    }
  end

  defp liste(attrs, key) do
    attrs
    |> Map.get(key, Map.get(attrs, Atom.to_string(key), []))
    |> werte()
  end

  defp werte(nil), do: []
  defp werte(%MapSet{} = menge), do: MapSet.to_list(menge)
  defp werte(liste) when is_list(liste), do: liste
  defp werte(einzeln), do: [einzeln]

  @doc "Ob der Ausschnitt gar nichts einschränkt — also alles meint."
  def empty?(%__MODULE__{} = scope) do
    scope.seasons == [] and scope.competition_ids == [] and
      scope.team_ids == [] and scope.kit_types == []
  end

  @doc """
  Ob zwei Ausschnitte dasselbe meinen.

  Die Reihenfolge innerhalb einer Achse zählt nicht — „HSV, BVB" ist derselbe
  Ausschnitt wie „BVB, HSV". Gebraucht für geteilte Ranglisten, bei denen
  jemand mit *genau denselben* Einstellungen antreten soll.
  """
  def same?(%__MODULE__{} = a, %__MODULE__{} = b) do
    Enum.all?([:seasons, :competition_ids, :team_ids, :kit_types], fn achse ->
      MapSet.new(Map.fetch!(a, achse)) == MapSet.new(Map.fetch!(b, achse))
    end)
  end

  def same?(a, b), do: same?(new(a), new(b))
end
