defmodule Kitrank.Kits.Kit do
  @moduledoc """
  Ein einzelnes Trikot eines Teams in einer Saison.

  Bilder werden nicht gehostet, sondern verlinkt (siehe Architektur Abschnitt 5):
  `cutout_url` für die Freisteller-Ansicht, `model_image_urls` für die Galerie.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kit_types ~w(home away third special)
  def kit_types, do: @kit_types

  @labels %{
    "home" => "Heim",
    "away" => "Auswärts",
    "third" => "Ausweich",
    "special" => "Sonder"
  }

  @doc "Deutsches Label für einen Kit-Typ, für die Anzeige in der UI."
  def label(kit_type), do: Map.get(@labels, kit_type, kit_type)

  schema "kits" do
    field :season, :string
    field :kit_type, :string
    field :cutout_url, :string
    field :model_image_urls, {:array, :string}, default: []
    field :source_shop_url, :string

    belongs_to :team, Kitrank.Kits.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(kit, attrs) do
    kit
    |> cast(attrs, [
      :team_id,
      :season,
      :kit_type,
      :cutout_url,
      :model_image_urls,
      :source_shop_url
    ])
    |> validate_required([:team_id, :season, :kit_type])
    |> Kitrank.Kits.Season.validate(:season)
    |> validate_inclusion(:kit_type, @kit_types)
    |> Kitrank.Kits.Url.validate_http_url(:cutout_url)
    |> Kitrank.Kits.Url.validate_http_url(:source_shop_url)
    |> Kitrank.Kits.Url.validate_http_url_list(:model_image_urls)
    |> assoc_constraint(:team)
    |> unique_constraint([:team_id, :season, :kit_type],
      message: "dieses Team hat für diese Saison schon ein Trikot dieses Typs"
    )
  end
end
