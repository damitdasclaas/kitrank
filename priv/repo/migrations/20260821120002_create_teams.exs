defmodule Kitrank.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :name, :string, null: false
      add :short_code, :string, null: false
      add :primary_color, :string
      add :shop_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:short_code])
  end
end
