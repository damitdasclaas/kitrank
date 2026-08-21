defmodule Kitrank.Kits.Competition do
  @moduledoc """
  Wettbewerb/Liga, z. B. "Bundesliga" (DE, Tier 1).

  `tier` steuert Sortierung und Gruppierung in der Übersicht – bewusst nicht aus
  dem Namen geparst, damit ausländische Ligen ohne Sonderfall funktionieren.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "competitions" do
    field :name, :string
    field :country, :string
    field :tier, :integer

    belongs_to :sport, Kitrank.Kits.Sport
    has_many :team_seasons, Kitrank.Kits.TeamSeason

    timestamps(type: :utc_datetime)
  end

  def changeset(competition, attrs) do
    competition
    |> cast(attrs, [:sport_id, :name, :country, :tier])
    |> validate_required([:sport_id, :name, :country, :tier])
    |> validate_format(:country, ~r/^[A-Z]{2}$/, message: "ISO-Ländercode, z. B. DE")
    |> validate_number(:tier, greater_than: 0)
    |> assoc_constraint(:sport)
    |> unique_constraint([:sport_id, :country, :name])
  end
end
