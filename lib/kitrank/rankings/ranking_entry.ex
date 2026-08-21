defmodule Kitrank.Rankings.RankingEntry do
  @moduledoc """
  Ein Trikot auf einem Platz einer Rangliste, mit optionaler Notiz.

  `position` ist 1-basiert: 1 ist der beste Platz. Das Reveal zählt von der
  höchsten Position runter auf 1.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ranking_entries" do
    field :position, :integer
    field :note, :string

    belongs_to :ranking, Kitrank.Rankings.Ranking
    belongs_to :kit, Kitrank.Kits.Kit

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:ranking_id, :kit_id, :position, :note])
    |> validate_required([:ranking_id, :kit_id, :position])
    |> validate_number(:position, greater_than: 0)
    |> validate_length(:note, max: 500)
    |> assoc_constraint(:ranking)
    |> assoc_constraint(:kit)
    |> unique_constraint([:ranking_id, :kit_id],
      message: "dieses Trikot steht schon in der Rangliste"
    )
  end
end
