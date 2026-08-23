defmodule Kitrank.Repo.Migrations.AddCutoutThumbUrl do
  use Ecto.Migration

  @moduledoc """
  Die kleine Variante, die der Shop selbst anbietet.

  Warum eine eigene Spalte und keine Ableitung: bei einigen Shops steckt die
  Größe nicht in der Adresse, sondern in einem signierten Token — bei TSG
  `?context=bWFzdGVy…`, das den Pfad kodiert. Aus der 1200er-Adresse lässt sich
  die 515er nicht errechnen, obwohl der Shop sie ausliefert. Also merken wir
  sie uns beim Einlesen.

  `text`, nicht `varchar(255)`: eine dieser Adressen war 352 Zeichen lang und
  hat die Oberfläche mit einem rohen Postgres-Fehler abgeräumt.
  """
  def change do
    alter table(:kits) do
      add :cutout_thumb_url, :text
    end
  end
end
