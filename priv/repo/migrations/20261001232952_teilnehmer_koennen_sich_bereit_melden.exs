defmodule Kitrank.Repo.Migrations.TeilnehmerKoennenSichBereitMelden do
  use Ecto.Migration

  @moduledoc """
  Der Host konnte bisher starten, sobald der Raum nicht leer war – egal ob
  wer noch mitten im eigenen Duell steckte. Jede:r meldet sich jetzt selbst
  bereit, der Host sieht ehrlich "3/5 bereit" statt nur "irgendwer ist da".
  """

  def change do
    alter table(:reveal_participants) do
      add :ready, :boolean, null: false, default: false
    end
  end
end
