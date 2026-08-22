defmodule Kitrank.Reveal.Participant do
  @moduledoc """
  Teilnahme einer Rangliste an einem Reveal-Raum.

  Verknüpft wird über den `share_slug`, den die Person beim Beitritt eingibt –
  ihr `edit_token` bleibt dabei privat.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "reveal_participants" do
    field :display_name, :string

    # Der Rang, den diese Person zuletzt selbst aufgedeckt hat.
    field :revealed_step, :integer

    belongs_to :room, Kitrank.Reveal.Room
    belongs_to :ranking, Kitrank.Rankings.Ranking

    timestamps(type: :utc_datetime)
  end

  @doc "Markiert diese Runde als aufgedeckt."
  def reveal_changeset(participant, step) do
    change(participant, revealed_step: step)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:room_id, :ranking_id, :display_name])
    |> validate_required([:room_id, :ranking_id, :display_name])
    |> update_change(:display_name, &String.trim/1)
    |> validate_length(:display_name, min: 1, max: 40)
    |> assoc_constraint(:room)
    |> assoc_constraint(:ranking)
    |> unique_constraint([:room_id, :ranking_id],
      message: "diese Rangliste ist dem Raum schon beigetreten"
    )
  end
end
