defmodule Kitrank.Repo.Migrations.CreateRankingEntries do
  use Ecto.Migration

  def change do
    create table(:ranking_entries) do
      add :ranking_id, references(:rankings, on_delete: :delete_all), null: false
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:ranking_entries, [:ranking_id, :position])
    # Ein Trikot taucht pro Rangliste nur einmal auf.
    create unique_index(:ranking_entries, [:ranking_id, :kit_id])
  end
end
