defmodule Kitrank.Repo.Migrations.GeteilteRanglistenMitGate do
  use Ecto.Migration

  @doc """
  Wie eine Rangliste geteilt wird — und woher eine abgeleitete kommt.

  `share_mode` unterscheidet zwei Absichten: „schau's dir an" und „erst selbst
  ranken, dann zeig ich meine". Das Zweite ist der interessantere Fall, weil es
  die Reihenfolge erzwingt, in der ein Vergleich überhaupt etwas taugt: wer die
  fremde Liste vorher sieht, rankt nicht mehr unbefangen.

  `derived_from_id` sagt, welche fremde Liste eine eigene freischaltet.
  `nilify_all`, nicht `delete_all`: verschwindet das Original, bleibt die
  selbst gebaute Liste bestehen. Sie gehört jemand anderem.
  """
  def change do
    alter table(:rankings) do
      add :share_mode, :string, null: false, default: "open"
      add :derived_from_id, references(:rankings, on_delete: :nilify_all)
    end

    create index(:rankings, [:derived_from_id])
  end
end
