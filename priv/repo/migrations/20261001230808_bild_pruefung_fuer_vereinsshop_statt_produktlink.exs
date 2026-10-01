defmodule Kitrank.Repo.Migrations.BildPruefungFuerVereinsshopStattProduktlink do
  use Ecto.Migration

  @moduledoc """
  Seit dem vorherigen Commit zeigt öffentlich nur noch der Vereinsshop-Link
  (`teams.shop_url`), nicht mehr der Produktlink pro Trikot
  (`kits.source_shop_url`) – der ist jetzt rein intern für den Bilder-Picker.
  Die Prüfung soll deshalb den Vereinsshop-Link checken statt den Produktlink.

  Ein Fund gehört ab jetzt entweder zu einem Kit (Bild-Adressen) oder zu
  einem Team (Vereinsshop), nie zu beidem – daher `kit_id` nullable und ein
  neues `team_id` mit Constraint, dass genau eins gesetzt ist.
  """

  def up do
    alter table(:image_check_findings) do
      modify :kit_id, :bigint, null: true
      add :team_id, references(:teams, on_delete: :delete_all)
    end

    drop unique_index(:image_check_findings, [:kit_id, :feld, :url])
    create unique_index(:image_check_findings, [:kit_id, :team_id, :feld, :url])

    create constraint(:image_check_findings, :kit_oder_team,
             check: "(kit_id IS NOT NULL) <> (team_id IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:image_check_findings, :kit_oder_team)
    drop unique_index(:image_check_findings, [:kit_id, :team_id, :feld, :url])
    create unique_index(:image_check_findings, [:kit_id, :feld, :url])

    alter table(:image_check_findings) do
      remove :team_id
      modify :kit_id, :bigint, null: false
    end
  end
end
