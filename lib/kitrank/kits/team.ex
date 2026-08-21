defmodule Kitrank.Kits.Team do
  @moduledoc """
  Verein. Stammdaten bleiben über Saisons hinweg stabil – die Liga-Zugehörigkeit
  hängt an `TeamSeason`, nicht hier, damit Auf-/Abstieg keine Stammdaten anfasst.

  Ein Team braucht kein `sport_id`: die Sportart ergibt sich transitiv über die
  Competition seiner TeamSeasons.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string
    field :short_code, :string
    field :primary_color, :string
    field :shop_url, :string

    has_many :team_seasons, Kitrank.Kits.TeamSeason
    has_many :kits, Kitrank.Kits.Kit

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :short_code, :primary_color, :shop_url])
    |> validate_required([:name, :short_code])
    |> update_change(:short_code, &String.upcase/1)
    |> validate_length(:short_code, min: 2, max: 5)
    |> validate_format(:primary_color, ~r/^#[0-9a-fA-F]{6}$/, message: "Hex-Farbe, z. B. #DC052D")
    |> Kitrank.Kits.Url.validate_http_url(:shop_url)
    |> unique_constraint(:short_code)
  end
end
