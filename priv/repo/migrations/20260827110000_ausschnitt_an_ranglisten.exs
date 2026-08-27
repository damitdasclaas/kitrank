defmodule Kitrank.Repo.Migrations.AusschnittAnRanglisten do
  use Ecto.Migration

  @doc """
  Der Ausschnitt, mit dem eine Rangliste gebaut wurde.

  Bisher war er flüchtig: `init_scope` baute ihn beim Laden aus den vorhandenen
  Einträgen neu zusammen. Tab zu, Einstellungen weg — und teilen ließ sich
  nichts, weil es nichts gab.

  Vier Spalten statt einer JSON-Spalte, wie bei `reveal_rooms`: so lässt sich
  in SQL nachsehen, womit jemand gearbeitet hat, ohne erst etwas auszupacken.
  Jede leere Liste heißt „keine Einschränkung" — der Standardwert ist damit
  „alles", genau wie ein frisch angelegter Ausschnitt.
  """
  def change do
    alter table(:rankings) do
      add :scope_seasons, {:array, :string}, null: false, default: []
      add :scope_competition_ids, {:array, :integer}, null: false, default: []
      add :scope_team_ids, {:array, :integer}, null: false, default: []
      add :scope_kit_types, {:array, :string}, null: false, default: []
    end
  end
end
