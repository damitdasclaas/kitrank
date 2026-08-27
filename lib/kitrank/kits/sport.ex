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

    has_many :competitions, Kitrank.Kits.Competition

    timestamps(type: :utc_datetime)
  end

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
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "nur Kleinbuchstaben, Ziffern und -")
    |> validate_exclusion(:slug, @reserviert,
      message: "ist schon ein Pfad der Anwendung — nimm einen anderen"
    )
    |> unique_constraint(:slug)
  end
end
