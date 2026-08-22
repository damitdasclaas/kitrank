defmodule Kitrank.Repo.Migrations.AddScopeToRevealRooms do
  use Ecto.Migration

  def change do
    # Der Raum legt fest, worum es geht – Saison, Ligen, Kit-Typen. Beim
    # Aufdecken zaehlen dann nur Trikots aus diesem Ausschnitt, und zwar in
    # jeder Rangliste dieselben.
    #
    # Ohne das vergleicht der Reveal Rang gegen Rang ueber voellig
    # verschiedene Mengen: "Platz 2" heisst bei einer Zweierliste "mein
    # schlechtestes" und bei einer Neunerliste "fast mein bestes".
    alter table(:reveal_rooms) do
      add :season, :string
      add :competition_ids, {:array, :integer}, null: false, default: []
      add :kit_types, {:array, :string}, null: false, default: []
    end
  end
end
