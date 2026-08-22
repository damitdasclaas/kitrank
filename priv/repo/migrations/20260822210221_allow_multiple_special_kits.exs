defmodule Kitrank.Repo.Migrations.AllowMultipleSpecialKits do
  use Ecto.Migration

  def up do
    # Ein Name, um Trikots desselben Typs zu unterscheiden – "125 Jahre",
    # "Weihnachten". Fuer Heim/Auswaerts/Ausweich unnoetig, fuer Sondertrikots
    # der einzige Weg, sie auseinanderzuhalten.
    alter table(:kits) do
      add :name, :string
    end

    drop unique_index(:kits, [:team_id, :season, :kit_type])

    # Heim, Auswaerts und Ausweich gibt es weiterhin genau einmal pro Saison.
    create unique_index(:kits, [:team_id, :season, :kit_type],
             where: "kit_type <> 'special'",
             name: :kits_regular_type_index
           )

    # Sondertrikots beliebig oft – aber nicht zweimal mit demselben Namen,
    # sonst waere die Liste wieder nicht lesbar.
    create unique_index(:kits, [:team_id, :season, :name],
             where: "kit_type = 'special'",
             name: :kits_special_name_index
           )
  end

  def down do
    drop index(:kits, [:team_id, :season, :name], name: :kits_special_name_index)
    drop index(:kits, [:team_id, :season, :kit_type], name: :kits_regular_type_index)

    create unique_index(:kits, [:team_id, :season, :kit_type])

    alter table(:kits) do
      remove :name
    end
  end
end
