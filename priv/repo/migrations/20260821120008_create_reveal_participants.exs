defmodule Kitrank.Repo.Migrations.CreateRevealParticipants do
  use Ecto.Migration

  def change do
    create table(:reveal_participants) do
      add :room_id, references(:reveal_rooms, on_delete: :delete_all), null: false
      add :ranking_id, references(:rankings, on_delete: :delete_all), null: false
      add :display_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:reveal_participants, [:room_id])
    # Dieselbe Rangliste tritt einem Raum nur einmal bei.
    create unique_index(:reveal_participants, [:room_id, :ranking_id])
  end
end
