defmodule Kitrank.Kits.ImageFinding do
  @moduledoc """
  Ein gemerkter Fund von `Kitrank.Kits.ImageCheck` – anders als dessen eigenes
  Rückgabeformat landet das hier in der Datenbank, damit eine Markierung als
  "erledigt" einen Neustart oder den nächsten Lauf übersteht.

  Gehört entweder zu einem Kit (eine der Bild-Adressen) oder zu einem Team
  (der Vereinsshop-Link) – nie zu beidem, das erzwingt die Datenbank-Constraint
  `kit_oder_team`.
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
    belongs_to :team, Kitrank.Kits.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :kit_id,
      :team_id,
      :feld,
      :url,
      :beschreibung,
      :kategorie,
      :status,
      :last_seen_at
    ])
    |> validate_required([:feld, :url, :beschreibung, :kategorie, :status, :last_seen_at])
    |> validate_inclusion(:status, @status)
    |> validate_genau_eine_quelle()
    |> assoc_constraint(:kit)
    |> assoc_constraint(:team)
    |> unique_constraint([:kit_id, :team_id, :feld, :url])
  end

  defp validate_genau_eine_quelle(changeset) do
    kit_id = get_field(changeset, :kit_id)
    team_id = get_field(changeset, :team_id)

    if is_nil(kit_id) == is_nil(team_id) do
      add_error(changeset, :kit_id, "genau eins von Kit oder Team muss gesetzt sein")
    else
      changeset
    end
  end
end
