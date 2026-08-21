defmodule Kitrank.Repo.Migrations.CreateCompetitions do
  use Ecto.Migration

  def change do
    create table(:competitions) do
      add :sport_id, references(:sports, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :country, :string, null: false
      add :tier, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:competitions, [:sport_id])
    # Eine Liga gibt es pro Sportart/Land nur einmal.
    create unique_index(:competitions, [:sport_id, :country, :name])
  end
end
