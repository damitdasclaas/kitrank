defmodule Kitrank.Reveal.Room do
  @moduledoc """
  Ein Reveal-Raum. Der State liegt komplett hier in Postgres, nicht in einem
  Prozess – dadurch überleben Reconnects (Handy sperrt, Tab neu geladen) ohne
  Sonderbehandlung: der LiveView lädt beim Remount einfach den aktuellen Stand.

  `current_step` ist der Rang, der gerade aufgedeckt ist, und zählt abwärts
  Richtung 1 – nicht ein Teilnehmer-Index.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(waiting revealing done)
  def statuses, do: @statuses

  # Ohne I, O, 0, 1 – der Code wird vorgelesen und abgetippt.
  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 5
  @default_ttl_hours 12

  schema "reveal_rooms" do
    field :room_code, :string
    field :status, :string, default: "waiting"
    field :current_step, :integer
    field :max_participants, :integer, default: 8
    field :host_token, :string
    field :expires_at, :utc_datetime

    has_many :participants, Kitrank.Reveal.Participant, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset für einen neuen Raum – Raumcode, Host-Token und Ablaufzeit werden
  serverseitig gesetzt und nicht aus `attrs` übernommen.
  """
  def create_changeset(room, attrs \\ %{}) do
    room
    |> cast(attrs, [:max_participants])
    |> validate_number(:max_participants, greater_than: 0, less_than_or_equal_to: 32)
    |> put_change(:room_code, generate_room_code())
    |> put_change(:host_token, generate_host_token())
    |> put_change(:expires_at, default_expiry())
    |> put_change(:status, "waiting")
    |> unique_constraint(:room_code)
  end

  @doc "Changeset für den Ablauf-State, den der Host weiterschaltet."
  def step_changeset(room, attrs) do
    room
    |> cast(attrs, [:status, :current_step])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_step, greater_than: 0)
  end

  @doc "PubSub-Topic und Presence-Topic eines Raums."
  def topic(room_code), do: "reveal:#{room_code}"

  @doc "Ist der Raum abgelaufen? Abgelaufene Räume liefern 404 statt stiller Fehler."
  def expired?(%__MODULE__{expires_at: expires_at}, now \\ DateTime.utc_now()) do
    DateTime.compare(now, expires_at) == :gt
  end

  defp default_expiry do
    DateTime.utc_now()
    |> DateTime.add(@default_ttl_hours * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp generate_room_code do
    alphabet_size = length(@code_alphabet)

    1..@code_length
    |> Enum.map(fn _ -> Enum.at(@code_alphabet, :rand.uniform(alphabet_size) - 1) end)
    |> List.to_string()
  end

  # Der Raumcode ist kurz und damit ratbar – die Host-Steuerung hängt deshalb an
  # einem eigenen, langen Token statt am Code.
  defp generate_host_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
