defmodule Kitrank.Repo.Migrations.BildPruefungMerktSichErledigtes do
  use Ecto.Migration

  @moduledoc """
  Ein Fund von `Kitrank.Kits.ImageCheck` ist sonst flüchtig – jeder Lauf fängt
  bei null an. Das reicht nicht, sobald man einen Fund als erledigt markieren
  will: ohne eigene Zeile vergisst der nächste Lauf das sofort wieder.

  `(kit_id, feld, url)` eindeutig: derselbe Fund über mehrere Läufe hinweg ist
  derselbe Datensatz, nicht ein neuer pro Lauf.
  """

  def change do
    create table(:image_check_findings) do
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :feld, :string, null: false
      # text, nicht varchar(255) – siehe 20260822214033_urls_ohne_laengengrenze.
      add :url, :text, null: false
      add :beschreibung, :string, null: false
      add :kategorie, :string, null: false
      add :status, :string, null: false, default: "offen"
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:image_check_findings, [:kit_id, :feld, :url])
    create index(:image_check_findings, [:status])
  end
end
