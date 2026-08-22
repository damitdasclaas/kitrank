defmodule KitrankWeb.Presence do
  @moduledoc """
  Wer ist gerade in einem Reveal-Raum online.

  Ergänzt `reveal_participants` in der Datenbank: dort steht, wer mitspielt,
  hier, wer gerade wirklich verbunden ist – nach einem Reconnect trackt der
  LiveView sich einfach neu.
  """
  use Phoenix.Presence,
    otp_app: :kitrank,
    pubsub_server: Kitrank.PubSub

  alias Kitrank.Reveal.Room

  @doc "Meldet den aktuellen LiveView als anwesend im Raum an."
  def track_participant(room_code, participant_id, meta) do
    track(self(), Room.topic(room_code), participant_id, meta)
  end

  @doc "Alle gerade verbundenen Teilnehmer eines Raums."
  def list_room(room_code), do: list(Room.topic(room_code))

  @doc "Das Topic, auf dem Presence seine Änderungen meldet – dasselbe wie im Reveal."
  def topic(room_code), do: Room.topic(room_code)
end
