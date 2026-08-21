defmodule Kitrank.Repo.Migrations.CreateKits do
  use Ecto.Migration

  def change do
    create table(:kits) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :season, :string, null: false
      add :kit_type, :string, null: false
      add :cutout_url, :string
      add :model_image_urls, {:array, :string}, null: false, default: []
      add :source_shop_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:kits, [:team_id, :season])
    # Pro Team/Saison jeden Kit-Typ nur einmal.
    create unique_index(:kits, [:team_id, :season, :kit_type])
  end
end
