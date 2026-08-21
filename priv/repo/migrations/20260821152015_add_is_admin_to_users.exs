defmodule Kitrank.Repo.Migrations.AddIsAdminToUsers do
  use Ecto.Migration

  def change do
    # Ein Flag statt eines Rollensystems: es gibt genau eine Sonderrolle, und
    # die pflegt niemand ueber die Oberflaeche, sondern der Betreiber per
    # Mix-Task. Sobald es mehr als "Admin oder nicht" gibt, wird daraus eine
    # eigene Tabelle – vorher waere sie leerer Aufwand.
    alter table(:users) do
      add :is_admin, :boolean, null: false, default: false
    end

    create index(:users, [:is_admin], where: "is_admin", name: :users_admins_index)
  end
end
