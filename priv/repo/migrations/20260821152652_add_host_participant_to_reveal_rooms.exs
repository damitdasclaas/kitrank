defmodule Kitrank.Repo.Migrations.AddHostParticipantToRevealRooms do
  use Ecto.Migration

  def change do
    # Die Steuerung ist uebertragbar: der Ersteller kann sie an einen
    # Teilnehmer abgeben, etwa wenn er selbst nur zuschaut oder das Geraet
    # wechselt. Sein host_token bleibt daneben gueltig, damit ein Raum nicht
    # unsteuerbar wird, wenn der neue Host offline geht.
    alter table(:reveal_rooms) do
      add :host_participant_id,
          references(:reveal_participants, on_delete: :nilify_all)
    end

    create index(:reveal_rooms, [:host_participant_id])
  end
end
