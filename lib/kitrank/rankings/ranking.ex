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

    # Womit die Liste gebaut wurde. Vier Spalten und kein JSON, damit man in
    # SQL nachsehen kann, ohne erst etwas auszupacken – und weil reveal_rooms
    # es genauso hält.
    field :scope_seasons, {:array, :string}, default: []
    field :scope_competition_ids, {:array, :integer}, default: []
    field :scope_team_ids, {:array, :integer}, default: []
    field :scope_kit_types, {:array, :string}, default: []

    # Wie geteilt wird. „gated" heisst: wer den Link oeffnet, muss erst selbst
    # ranken — mit demselben Ausschnitt.
    field :share_mode, :string, default: "open"

    # Welche fremde Liste diese hier freischaltet.
    belongs_to :derived_from, __MODULE__, foreign_key: :derived_from_id

    has_many :entries, Kitrank.Rankings.RankingEntry, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @share_modes ~w(open gated)

  @doc """
  Die beiden Arten zu teilen.

    * `"open"` – wer den Link hat, sieht die Liste.
    * `"gated"` – wer den Link hat, muss erst selbst ranken. Erst danach wird
      beides gezeigt und verglichen.

  Der zweite Fall erzwingt die Reihenfolge, in der ein Vergleich überhaupt
  etwas taugt: wer die fremde Liste vorher sieht, rankt nicht mehr unbefangen.
  """
  def share_modes, do: @share_modes

  def gated?(%__MODULE__{share_mode: "gated"}), do: true
  def gated?(%__MODULE__{}), do: false

  def derived?(%__MODULE__{derived_from_id: id}), do: not is_nil(id)

  @scope_felder [:scope_seasons, :scope_competition_ids, :scope_team_ids, :scope_kit_types]

  @doc """
  Der gespeicherte Ausschnitt als `Kitrank.Kits.Scope`.

  Vor dieser Änderung gab es ihn nur im Speicher der offenen Sitzung. Für alte
  Ranglisten sind die Spalten leer — und ein leerer Ausschnitt heißt „alles",
  was der ehrlichste Ersatz für „wir wissen es nicht mehr" ist.
  """
  def scope(%__MODULE__{} = ranking) do
    %Kitrank.Kits.Scope{
      seasons: ranking.scope_seasons,
      competition_ids: ranking.scope_competition_ids,
      team_ids: ranking.scope_team_ids,
      kit_types: ranking.scope_kit_types
    }
  end

  @doc "Changeset, der nur den Ausschnitt setzt."
  def scope_changeset(%__MODULE__{} = ranking, scope) do
    scope = Kitrank.Kits.Scope.new(scope)

    change(ranking,
      scope_seasons: scope.seasons,
      scope_competition_ids: scope.competition_ids,
      scope_team_ids: scope.team_ids,
      scope_kit_types: scope.kit_types
    )
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
    |> cast(attrs, [:display_name, :share_mode | @scope_felder])
    |> validate_display_name()
    |> validate_subset(:scope_kit_types, Kitrank.Kits.Kit.kit_types())
    |> validate_inclusion(:share_mode, @share_modes)
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
