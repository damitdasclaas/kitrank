defmodule Kitrank.Repo.Migrations.AddRevealedStepToParticipants do
  use Ecto.Migration

  def change do
    # Jeder deckt sein eigenes Trikot auf. Gespeichert wird der Rang, den diese
    # Person zuletzt aufgedeckt hat – "hat diese Runde schon aufgedeckt" ist
    # dann einfach `revealed_step == room.current_step`.
    #
    # Eine Spalte statt einer Tabelle pro Aufdeckung: Ein Teilnehmer hat pro
    # Runde genau einen Zustand, und die Runden zaehlen abwaerts. Damit braucht
    # es auch kein Zuruecksetzen beim Weiterschalten – der alte Wert passt
    # einfach nicht mehr zum neuen Rang.
    alter table(:reveal_participants) do
      add :revealed_step, :integer
    end
  end
end
