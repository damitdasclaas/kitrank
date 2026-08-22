defmodule KitrankWeb.KitLabel do
  @moduledoc """
  Beschriftungen für Trikots – übersetzbar.

  Die Bezeichnungen liegen hier und nicht im Schema: welche Trikot-Typen es
  gibt, ist eine Sachfrage der Domäne (`Kitrank.Kits.Kit.kit_types/0`), wie sie
  in welcher Sprache heißen, eine der Darstellung. Andernfalls müsste
  `Kitrank.Kits.Kit` die Sprache des Betrachters kennen und die Domäne von der
  Weboberfläche abhängen.

  Gettext braucht die Zeichenkette wörtlich im Quelltext, damit `extract` sie
  findet – deshalb ein `case` mit Literalen und keine Nachschlagetabelle.
  """
  use Gettext, backend: KitrankWeb.Gettext

  alias Kitrank.Kits.Kit

  @doc "Bezeichnung eines Trikot-Typs in der Sprache des Betrachters."
  def label("home"), do: gettext("Heim")
  def label("away"), do: gettext("Auswärts")
  def label("third"), do: gettext("Ausweich")
  def label("special"), do: gettext("Sonder")
  def label(other), do: other

  @doc """
  Beschriftung eines konkreten Trikots.

  Sondertrikots gibt es pro Saison beliebig viele – ohne ihren Namen stünde in
  jeder Liste mehrfach dasselbe "Sonder". Bei Heim, Auswärts und Ausweich ist
  der Name überflüssig, dort bleibt es beim Typ.
  """
  def display(%Kit{kit_type: kit_type, name: name}) when is_binary(name) do
    if String.trim(name) == "", do: label(kit_type), else: "#{label(kit_type)} · #{name}"
  end

  def display(%Kit{kit_type: kit_type}), do: label(kit_type)

  @doc """
  Rolle eines Bildes an einer Position.

  Konvention der Datenpflege: 1 Freisteller vorn, 2 Rückseite, ab 3 Model.
  """
  def image_role(0), do: gettext("Vorderseite")
  def image_role(1), do: gettext("Rückseite")
  def image_role(index), do: gettext("Model %{nr}", nr: index - 1)
end
