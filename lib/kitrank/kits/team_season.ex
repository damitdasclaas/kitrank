defmodule Kitrank.Kits.TeamSeason do
  @moduledoc """
  Verknüpft Team ↔ Competition ↔ Saison. Der Dreh- und Angelpunkt für
  Auf-/Abstieg: pro Saison ein Eintrag, gepflegt über die Admin-UI.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_seasons" do
    field :season, :string

    belongs_to :team, Kitrank.Kits.Team
    belongs_to :competition, Kitrank.Kits.Competition

    timestamps(type: :utc_datetime)
  end

  def changeset(team_season, attrs) do
    team_season
    |> cast(attrs, [:team_id, :competition_id, :season])
    |> validate_required([:team_id, :competition_id, :season])
    |> Kitrank.Kits.Season.validate(:season)
    |> assoc_constraint(:team)
    |> assoc_constraint(:competition)
    |> unique_constraint([:team_id, :season],
      message: "dieses Team ist in dieser Saison schon einer Liga zugeordnet"
    )
  end
end
