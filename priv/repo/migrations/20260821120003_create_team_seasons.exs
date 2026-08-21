defmodule Kitrank.Repo.Migrations.CreateTeamSeasons do
  use Ecto.Migration

  def change do
    create table(:team_seasons) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :competition_id, references(:competitions, on_delete: :restrict), null: false
      add :season, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:team_seasons, [:competition_id, :season])
    # Ein Team spielt pro Saison in genau einer Liga.
    create unique_index(:team_seasons, [:team_id, :season])
  end
end
