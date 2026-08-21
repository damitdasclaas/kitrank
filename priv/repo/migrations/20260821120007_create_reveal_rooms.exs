defmodule Kitrank.Repo.Migrations.CreateRevealRooms do
  use Ecto.Migration

  def change do
    create table(:reveal_rooms) do
      add :room_code, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :current_step, :integer
      add :max_participants, :integer, null: false, default: 8
      add :host_token, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:reveal_rooms, [:room_code])
    create index(:reveal_rooms, [:expires_at])
  end
end
