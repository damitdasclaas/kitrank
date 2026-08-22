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

  schema "kits" do
    field :season, :string
    field :kit_type, :string
    field :name, :string
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
      :name,
      :cutout_url,
      :model_image_urls,
      :source_shop_url
    ])
    |> validate_required([:team_id, :season, :kit_type])
    |> update_change(:name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_length(:name, max: 60)
    |> require_name_for_special()
    |> Kitrank.Kits.Season.validate(:season)
    |> validate_inclusion(:kit_type, @kit_types)
    |> Kitrank.Kits.Url.validate_http_url(:cutout_url)
    |> Kitrank.Kits.Url.validate_http_url(:source_shop_url)
    |> Kitrank.Kits.Url.validate_http_url_list(:model_image_urls)
    |> assoc_constraint(:team)
    |> unique_constraint([:team_id, :season, :kit_type],
      name: :kits_regular_type_index,
      message: "dieses Team hat für diese Saison schon ein Trikot dieses Typs"
    )
    |> unique_constraint([:team_id, :season, :name],
      name: :kits_special_name_index,
      message: "dieses Team hat für diese Saison schon ein Sondertrikot mit diesem Namen"
    )
  end

  # Ohne Namen sind mehrere Sondertrikots nicht auseinanderzuhalten – deshalb
  # hier Pflicht und nur hier.
  defp require_name_for_special(changeset) do
    if get_field(changeset, :kit_type) == "special" do
      changeset
      |> validate_required([:name],
        message: "Sondertrikots brauchen einen Namen, um sie zu unterscheiden"
      )
      |> validate_length(:name, min: 1)
    else
      changeset
    end
  end
end
