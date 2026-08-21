defmodule Kitrank.Repo.Migrations.CreateSports do
  use Ecto.Migration

  def change do
    create table(:sports) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sports, [:slug])
  end
end
