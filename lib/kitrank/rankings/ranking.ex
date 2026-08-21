defmodule Kitrank.Rankings.Ranking do
  @moduledoc """
  Eine persönliche Rangliste. Kein Login – der Zugriff hängt an zwei Tokens:

    * `edit_token` – lang und kryptografisch zufällig, gibt Bearbeitungsrecht
    * `share_slug` – kurz und öffentlich, gibt nur Leserecht

  Beide zeigen auf denselben Datensatz, der Share-Link ist damit immer aktuell.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @edit_token_bytes 24
  @share_slug_bytes 6

  schema "rankings" do
    field :edit_token, :string
    field :share_slug, :string
    field :display_name, :string

    has_many :entries, Kitrank.Rankings.RankingEntry, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset für eine neue Rangliste – erzeugt die Tokens selbst.

  Sie werden bewusst nicht aus `attrs` übernommen, damit sie nicht von außen
  gesetzt werden können.
  """
  def create_changeset(ranking, attrs \\ %{}) do
    ranking
    |> cast(attrs, [:display_name])
    |> validate_display_name()
    |> put_change(:edit_token, generate_token(@edit_token_bytes))
    |> put_change(:share_slug, generate_token(@share_slug_bytes))
    |> unique_constraint(:edit_token)
    |> unique_constraint(:share_slug)
  end

  @doc "Changeset für alles, was der Besitzer später ändern darf."
  def changeset(ranking, attrs) do
    ranking
    |> cast(attrs, [:display_name])
    |> validate_display_name()
  end

  defp validate_display_name(changeset) do
    changeset
    |> update_change(:display_name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_length(:display_name, max: 60)
  end

  # 24 Byte ≈ 192 bit Entropie beim edit_token, deutlich über den in der
  # Architektur geforderten 128 bit. base64url, damit der Token URL-sicher ist.
  defp generate_token(bytes) do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
