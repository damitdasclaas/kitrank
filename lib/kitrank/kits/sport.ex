defmodule Kitrank.Kits.Sport do
  @moduledoc """
  Sportart. Heute steht hier nur "Fußball" drin – die Tabelle existiert, damit
  eine zweite Sportart später ein Datensatz statt einer Migration ist.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sports" do
    field :name, :string
    field :slug, :string
    field :kit_types, {:array, :string}, default: ~w(home away third special)
    field :special_label, :string

    has_many :competitions, Kitrank.Kits.Competition

    timestamps(type: :utc_datetime)
  end

  @doc """
  Die Kategorien, die diese Sportart anbietet — in Anzeige-Reihenfolge.

  Fußball kennt Heim, Auswärts, Ausweich und Sondertrikots; die NFL Heim,
  Auswärts und Alternates. Die Struktur ist dieselbe, nur die Auswahl nicht.

  Bewusst keine Datenbank-Bedingung: `Kit.kit_type` prüft weiter gegen die
  globale Liste. Die Sportart eines Trikots hängt transitiv über Verein →
  Saison-Zuordnung → Liga, und ein Verein könnte in zwei Sportarten spielen —
  das würde den Kit-Changeset von einem Join abhängig machen. Die
  Import-Dateien sind pro Sportart und werden gelesen; das Risiko ist klein
  genug für die Vereinfachung.
  """
  def kit_types(%__MODULE__{kit_types: types}), do: types

  @doc """
  Die Kategorien, von denen es genau eine je Verein und Saison gibt.

  Sondertrikots sind der Gegenfall: von denen gibt es beliebig viele,
  unterschieden über ihren Namen. Der Import legt deshalb nur für diese hier
  leere Datensätze an — ein namenloses Sondertrikot gäbe es gar nicht.
  """
  def einzelne_kit_types(%__MODULE__{} = sport), do: kit_types(sport) -- ["special"]

  @doc """
  Pfade, die es schon gibt.

  Der Slug ist die Adresse der Sportart: `/football`. Diese Route steht ganz
  unten im Router und faengt alles ab, was davor nicht gepasst hat — eine
  Sportart mit dem Slug `reveal` wuerde die Reveal-Seite still verschlucken.
  Die Route zuletzt zu deklarieren reicht dagegen nicht: sie wuerde zwar nicht
  gewinnen, aber die Sportart waere dann unerreichbar, und niemand saehe warum.
  """
  @reserviert ~w(
    admin datenschutz dev impressum r rankings reveal sprache teams users
    vergleich
  )

  def reservierte_slugs, do: @reserviert

  def changeset(sport, attrs) do
    sport
    |> cast(attrs, [:name, :slug, :kit_types, :special_label])
    |> validate_required([:name, :slug, :kit_types])
    |> validate_subset(:kit_types, Kitrank.Kits.Kit.kit_types())
    |> validate_length(:kit_types, min: 1, message: "mindestens eine Kategorie")
    |> update_change(:special_label, fn
      nil -> nil
      label -> if String.trim(label) == "", do: nil, else: String.trim(label)
    end)
    |> validate_length(:special_label, max: 30)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "nur Kleinbuchstaben, Ziffern und -")
    |> validate_exclusion(:slug, @reserviert,
      message: "ist schon ein Pfad der Anwendung — nimm einen anderen"
    )
    |> unique_constraint(:slug)
  end
end
