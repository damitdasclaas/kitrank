defmodule Kitrank.Repo.Migrations.KitTypesProSportart do
  use Ecto.Migration

  @doc """
  Welche Trikot-Kategorien eine Sportart kennt.

  „Ausweichtrikot" gibt es in der NFL nicht, „Throwback" im Fußball nicht. Die
  Struktur bleibt dieselbe — von Heim/Auswärts/Ausweich genau eins pro Verein
  und Saison, von `special` beliebig viele mit Namen. Nur was angeboten wird,
  hängt jetzt an der Sportart.

  `special_label`, weil dasselbe Feld je Sportart anders heißt: „Sondertrikot"
  im Fußball, „Alternate" in der NFL. Nullable, dann bleibt es bei der
  übersetzten Vorgabe.
  """
  def change do
    alter table(:sports) do
      # Der bisherige globale Satz als Vorgabe: alle bestehenden Sportarten
      # verhalten sich nach der Migration exakt wie vorher.
      add :kit_types, {:array, :string}, null: false, default: ~w(home away third special)
      add :special_label, :string
    end
  end
end
