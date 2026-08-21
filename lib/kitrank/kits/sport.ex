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

  def changeset(sport, attrs) do
    sport
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "nur Kleinbuchstaben, Ziffern und -")
    |> unique_constraint(:slug)
  end
end
