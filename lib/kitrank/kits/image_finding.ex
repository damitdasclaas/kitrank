defmodule Kitrank.Kits.ImageFinding do
  @moduledoc """
  Ein gemerkter Fund von `Kitrank.Kits.ImageCheck` – anders als dessen eigenes
  Rückgabeformat landet das hier in der Datenbank, damit eine Markierung als
  "erledigt" einen Neustart oder den nächsten Lauf übersteht.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @status ~w(offen erledigt)
  def status_werte, do: @status

  schema "image_check_findings" do
    field :feld, :string
    field :url, :string
    field :beschreibung, :string
    field :kategorie, :string
    field :status, :string, default: "offen"
    field :last_seen_at, :utc_datetime

    belongs_to :kit, Kitrank.Kits.Kit

    timestamps(type: :utc_datetime)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [:kit_id, :feld, :url, :beschreibung, :kategorie, :status, :last_seen_at])
    |> validate_required([
      :kit_id,
      :feld,
      :url,
      :beschreibung,
      :kategorie,
      :status,
      :last_seen_at
    ])
    |> validate_inclusion(:status, @status)
    |> assoc_constraint(:kit)
    |> unique_constraint([:kit_id, :feld, :url])
  end
end
