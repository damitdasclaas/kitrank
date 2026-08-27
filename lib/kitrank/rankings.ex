defmodule Kitrank.Rankings do
  @moduledoc """
  Persönliche Ranglisten – Erstellen, Bearbeiten, Teilen.

  Zugriff läuft ohne Login über zwei Tokens: `edit_token` schreibt, `share_slug`
  liest. Beide zeigen auf denselben Datensatz, der Share-Link ist deshalb immer
  auf dem Live-Stand – es gibt keinen Export-Schritt.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Kitrank.Repo
  alias Kitrank.Kits
  alias Kitrank.Kits.Kit
  alias Kitrank.Rankings.{Ranking, RankingEntry}

  @doc """
  Legt eine leere Rangliste an und erzeugt dabei `edit_token` und `share_slug`.

  Die Trikots kommen erst beim Bearbeiten dazu – so gehören dem Ersteller keine
  Einträge zu Saisons, die er nie angefasst hat.
  """
  def create_ranking(attrs \\ %{}) do
    %Ranking{} |> Ranking.create_changeset(attrs) |> Repo.insert()
  end

  @doc """
  Legt eine Rangliste an, die schon alle Trikots der Saison in Übersichts-
  Reihenfolge enthält – als Startpunkt, den man nur noch umsortiert.
  """
  def create_ranking_with_all_kits(attrs \\ %{}, season \\ Kits.current_season()) do
    Multi.new()
    |> Multi.insert(:ranking, Ranking.create_changeset(%Ranking{}, attrs))
    |> Multi.run(:entries, fn _repo, %{ranking: ranking} ->
      kit_ids = season |> Kits.list_rankable_kits() |> Enum.map(& &1.id)
      {count, _} = insert_entries(ranking, kit_ids)
      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{ranking: ranking}} -> {:ok, ranking}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc "Rangliste per Bearbeitungs-Token. `nil`, wenn der Token nicht existiert."
  def get_ranking_by_edit_token(token) when is_binary(token) do
    Repo.get_by(Ranking, edit_token: token)
  end

  def get_ranking_by_edit_token(_), do: nil

  @doc "Rangliste per öffentlichem Share-Slug. `nil`, wenn der Slug nicht existiert."
  def get_ranking_by_share_slug(slug) when is_binary(slug) do
    Repo.get_by(Ranking, share_slug: slug)
  end

  def get_ranking_by_share_slug(_), do: nil

  def update_ranking(%Ranking{} = ranking, attrs) do
    ranking |> Ranking.changeset(attrs) |> Repo.update()
  end

  def change_ranking(%Ranking{} = ranking, attrs \\ %{}), do: Ranking.changeset(ranking, attrs)

  def delete_ranking(%Ranking{} = ranking), do: Repo.delete(ranking)

  @doc """
  Alle Einträge einer Rangliste, nach Position sortiert, mit Trikot und Team.

  Das ist die Abfrage hinter Edit-View, Share-View und Reveal – deshalb einmal
  zentral mit allen Preloads, die die Anzeige braucht.
  """
  def list_entries(%Ranking{id: ranking_id}), do: list_entries(ranking_id)

  def list_entries(ranking_id) do
    from(e in RankingEntry,
      where: e.ranking_id == ^ranking_id,
      order_by: [asc: e.position],
      preload: [kit: :team]
    )
    |> Repo.all()
  end

  @doc """
  Der Eintrag auf einem bestimmten Rang – die Abfrage, die das Reveal pro Schritt
  je Teilnehmer braucht. `nil`, wenn die Rangliste so weit nicht reicht.
  """
  def get_entry_at(ranking_id, position) do
    from(e in RankingEntry,
      where: e.ranking_id == ^ranking_id and e.position == ^position,
      preload: [kit: :team]
    )
    |> Repo.one()
  end

  @doc "Anzahl der Einträge – im Reveal der Startwert, von dem runtergezählt wird."
  def count_entries(ranking_id) do
    Repo.one(from e in RankingEntry, where: e.ranking_id == ^ranking_id, select: count(e.id))
  end

  @doc """
  Nimmt ein Trikot in die Rangliste auf und hängt es hinten an.

  Ist es schon drin, passiert nichts – der bestehende Eintrag (inklusive Notiz)
  bleibt unverändert.
  """
  def add_kit(%Ranking{} = ranking, kit_id) do
    case insert_entries(ranking, [kit_id]) do
      {0, _} -> {:ok, :already_present}
      {_, _} -> {:ok, :added}
    end
  end

  @doc """
  Nimmt mehrere Trikots auf einmal auf – für "ganze Liga hinzufügen".

  Gibt zurück, wie viele wirklich dazugekommen sind; bereits vorhandene werden
  übersprungen, ohne ihre Notiz zu verlieren.
  """
  def add_kits(%Ranking{} = ranking, kit_ids) when is_list(kit_ids) do
    {count, _} = insert_entries(ranking, kit_ids)
    count
  end

  @doc """
  Speichert den Ausschnitt, mit dem gerade gearbeitet wird.

  Bei jeder Änderung, nicht erst am Ende: der Ausschnitt ist das, was jemand
  eingestellt hat, und das soll einen geschlossenen Tab überleben.
  """
  def update_scope(%Ranking{} = ranking, scope) do
    ranking |> Ranking.scope_changeset(scope) |> Repo.update()
  end

  @doc """
  Die Trikots, um die es in dieser Rangliste geht.

  Ein leerer Ausschnitt heißt „alles" — für Ranglisten von vor der
  Ausschnitt-Speicherung ist das der ehrlichste Ersatz für „wir wissen es
  nicht mehr".
  """
  def kits_in_scope(%Ranking{} = ranking) do
    ranking |> Ranking.scope() |> Kits.list_kits_for_scope()
  end

  ## Teilen mit Gate

  @doc """
  Legt eine Rangliste an, die auf einer fremden aufsetzt.

  Sie übernimmt deren Ausschnitt — das ist der ganze Punkt: verglichen wird
  nur, was mit denselben Einstellungen gebaut wurde. Der Ausschnitt lässt sich
  an einer abgeleiteten Liste deshalb auch nicht ändern.
  """
  def create_derived(%Ranking{} = original, attrs \\ %{}) do
    scope = Ranking.scope(original)

    %Ranking{}
    |> Ranking.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:derived_from_id, original.id)
    |> Ecto.Changeset.put_change(:scope_seasons, scope.seasons)
    |> Ecto.Changeset.put_change(:scope_competition_ids, scope.competition_ids)
    |> Ecto.Changeset.put_change(:scope_team_ids, scope.team_ids)
    |> Ecto.Changeset.put_change(:scope_kit_types, scope.kit_types)
    |> Repo.insert()
  end

  @doc """
  Ob eine Rangliste vollständig ist: jedes Trikot des Ausschnitts hat einen
  Platz.

  Das ist die Schwelle, ab der eine geteilte Liste mit Gate freigeschaltet
  wird. Eine halbe Liste zu akzeptieren würde die Regel aushöhlen — man könnte
  drei Trikots einsortieren und wäre durch.
  """
  def complete?(%Ranking{} = ranking) do
    umfang = ranking |> kits_in_scope() |> length()

    umfang > 0 and count_entries(ranking.id) >= umfang
  end

  @doc """
  Sucht unter den Ranglisten dieses Browsers die, die eine fremde freischaltet.

  Gibt `{:passed, eigene}`, `{:building, eigene}` oder `:none` zurück.

  **Das ist eine Höflichkeitsschranke, keine Sicherheitsgrenze.** Ranglisten
  haben kein Login, der Nachweis kommt aus dem localStorage des Browsers — ein
  privates Fenster hebt sie auf. Für einen Abend unter Freunden reicht das;
  wer es dicht will, braucht Konten.

  Geprüft wird trotzdem beides: dass die eigene wirklich von dieser abgeleitet
  ist, **und** dass ihr Ausschnitt noch derselbe ist. Sonst würde eine
  nachträglich geänderte Einstellung den Vergleich still entwerten.
  """
  def gate_state(%Ranking{} = original, tokens) when is_list(tokens) do
    eigene =
      tokens
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&get_ranking_by_edit_token/1)
      |> Enum.filter(&passt_zum_original?(&1, original))

    cond do
      eigene == [] -> :none
      fertig = Enum.find(eigene, &complete?/1) -> {:passed, fertig}
      true -> {:building, hd(eigene)}
    end
  end

  defp passt_zum_original?(nil, _original), do: false

  defp passt_zum_original?(%Ranking{} = eigene, %Ranking{} = original) do
    eigene.derived_from_id == original.id and
      Kits.Scope.same?(Ranking.scope(eigene), Ranking.scope(original))
  end

  @doc """
  Die Rangliste, von der diese abgeleitet ist — oder `nil`.

  Gebraucht fuer den Weg zurueck: wer seine eigene Liste fertig hat, soll die
  fremde wiederfinden, ohne die Nachricht zu suchen, in der der Link stand.
  """
  def get_derived_from(%Ranking{derived_from_id: nil}), do: nil
  def get_derived_from(%Ranking{derived_from_id: id}), do: Repo.get(Ranking, id)

  @doc "Setzt, wie eine Rangliste geteilt wird."
  def set_share_mode(%Ranking{} = ranking, mode) do
    ranking |> Ranking.changeset(%{share_mode: mode}) |> Repo.update()
  end

  @doc "Nimmt ein Trikot wieder aus der Rangliste – identifiziert über das Trikot."
  def remove_kit(%Ranking{} = ranking, kit_id) do
    case Repo.get_by(RankingEntry, ranking_id: ranking.id, kit_id: kit_id) do
      nil -> {:ok, :not_present}
      entry -> with {:ok, _} <- remove_entry(entry), do: {:ok, :removed}
    end
  end

  @doc """
  Die Trikots einer Rangliste als `MapSet` – für die Auswahl-Ansicht, die für
  jede Kachel wissen muss, ob sie schon drin ist.
  """
  def selected_kit_ids(%Ranking{id: ranking_id}) do
    from(e in RankingEntry, where: e.ranking_id == ^ranking_id, select: e.kit_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Verschiebt einen Eintrag um `delta` Plätze; am Rand passiert nichts."
  def move_entry(%Ranking{} = ranking, kit_id, delta) do
    with_index(ranking, kit_id, fn ids, index ->
      target = index + delta

      if target < 0 or target >= length(ids), do: :ok, else: place(ranking, ids, index, target)
    end)
  end

  @doc """
  Setzt einen Eintrag auf einen bestimmten Platz, gezählt ab 1.

  Werte ausserhalb der Liste rutschen an den nächsten Rand: wer bei zwölf
  Einträgen die 99 eintippt, meint „ganz nach unten" und soll keinen Fehler
  vorgesetzt bekommen.
  """
  def move_to(%Ranking{} = ranking, kit_id, position) when is_integer(position) do
    with_index(ranking, kit_id, fn ids, index ->
      target = position |> max(1) |> min(length(ids)) |> Kernel.-(1)

      if target == index, do: :ok, else: place(ranking, ids, index, target)
    end)
  end

  defp with_index(ranking, kit_id, fun) do
    ids =
      Repo.all(
        from e in RankingEntry,
          where: e.ranking_id == ^ranking.id,
          order_by: e.position,
          select: e.kit_id
      )

    case Enum.find_index(ids, &(&1 == kit_id)) do
      nil -> {:error, :not_found}
      index -> fun.(ids, index)
    end
  end

  defp place(ranking, ids, index, target) do
    ids
    |> List.delete_at(index)
    |> List.insert_at(target, Enum.at(ids, index))
    |> then(&reorder(ranking, &1))
  end

  def remove_entry(%RankingEntry{} = entry) do
    Multi.new()
    |> Multi.delete(:entry, entry)
    |> Multi.run(:compact, fn _repo, _changes ->
      {:ok, close_position_gaps(entry.ranking_id)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry}} -> {:ok, entry}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Schreibt eine komplette neue Reihenfolge – `kit_ids` in Wunsch-Reihenfolge,
  Position 1 zuerst. Genau das schickt der Drag-Hook nach einem Umsortieren.

  Läuft in einer Transaktion und weist die Reihenfolge zurück, wenn sie nicht
  exakt die Trikots der Rangliste enthält; ein halb angewendetes Umsortieren wäre
  schlimmer als ein abgelehntes.
  """
  def reorder(%Ranking{} = ranking, kit_ids) when is_list(kit_ids) do
    existing_ids =
      Repo.all(from e in RankingEntry, where: e.ranking_id == ^ranking.id, select: e.kit_id)

    if MapSet.new(kit_ids) == MapSet.new(existing_ids) and length(kit_ids) == length(existing_ids) do
      kit_ids
      |> Enum.with_index(1)
      |> Enum.reduce(Multi.new(), fn {kit_id, position}, multi ->
        query =
          from e in RankingEntry,
            where: e.ranking_id == ^ranking.id and e.kit_id == ^kit_id

        Multi.update_all(multi, {:position, kit_id}, query, set: [position: position])
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> :ok
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, :kit_ids_mismatch}
    end
  end

  @doc "Setzt oder löscht die Notiz zu einem Eintrag (leerer Text -> keine Notiz)."
  def update_note(%RankingEntry{} = entry, note) do
    note = if is_binary(note) and String.trim(note) == "", do: nil, else: note

    entry
    |> RankingEntry.changeset(%{note: note})
    |> Repo.update()
  end

  # Hängt Trikots hinten an und ignoriert bereits vorhandene. Ein einzelnes
  # INSERT ... ON CONFLICT DO NOTHING statt N Roundtrips.
  defp insert_entries(%Ranking{} = ranking, kit_ids) do
    next = (max_position(ranking.id) || 0) + 1
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Nur Trikots, die es wirklich gibt – sonst würde der FK erst beim Insert
    # zuschlagen und die ganze Transaktion killen.
    valid_ids =
      Repo.all(from k in Kit, where: k.id in ^kit_ids, select: k.id) |> MapSet.new()

    rows =
      kit_ids
      |> Enum.filter(&MapSet.member?(valid_ids, &1))
      |> Enum.uniq()
      |> Enum.with_index(next)
      |> Enum.map(fn {kit_id, position} ->
        %{
          ranking_id: ranking.id,
          kit_id: kit_id,
          position: position,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(RankingEntry, rows, on_conflict: :nothing)
  end

  defp max_position(ranking_id) do
    Repo.one(from e in RankingEntry, where: e.ranking_id == ^ranking_id, select: max(e.position))
  end

  # Nach dem Löschen entstehen Lücken (1,2,4,...). Positionen werden neu
  # durchnummeriert, damit "Rang N" im Reveal auch wirklich der N-te Eintrag ist.
  defp close_position_gaps(ranking_id) do
    from(e in RankingEntry,
      where: e.ranking_id == ^ranking_id,
      order_by: [asc: e.position],
      select: e.id
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      Repo.update_all(from(e in RankingEntry, where: e.id == ^id), set: [position: position])
    end)
  end
end
