defmodule Kitrank.RankingsTest do
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures
  import Kitrank.RankingsFixtures

  alias Kitrank.Rankings

  describe "create_ranking/1" do
    test "erzeugt Tokens serverseitig" do
      {:ok, ranking} = Rankings.create_ranking(%{display_name: "Toms Liste"})

      # 24 Byte base64url ohne Padding = 32 Zeichen, also ~192 bit Entropie.
      assert String.length(ranking.edit_token) == 32
      assert String.length(ranking.share_slug) == 8
      assert ranking.display_name == "Toms Liste"
    end

    test "ignoriert von außen mitgeschickte Tokens" do
      {:ok, ranking} = Rankings.create_ranking(%{edit_token: "geraten", share_slug: "geraten"})

      refute ranking.edit_token == "geraten"
      refute ranking.share_slug == "geraten"
    end

    test "vergibt für jede Rangliste eigene Tokens" do
      {:ok, a} = Rankings.create_ranking()
      {:ok, b} = Rankings.create_ranking()

      refute a.edit_token == b.edit_token
      refute a.share_slug == b.share_slug
    end
  end

  describe "Zugriff über Tokens" do
    setup do
      %{ranking: ranking_fixture()}
    end

    test "findet die Rangliste über beide Wege", %{ranking: ranking} do
      assert Rankings.get_ranking_by_edit_token(ranking.edit_token).id == ranking.id
      assert Rankings.get_ranking_by_share_slug(ranking.share_slug).id == ranking.id
    end

    test "der Share-Slug öffnet nicht die Bearbeitung", %{ranking: ranking} do
      assert Rankings.get_ranking_by_edit_token(ranking.share_slug) == nil
    end

    test "unbekannte oder ungültige Werte liefern nil" do
      assert Rankings.get_ranking_by_edit_token("gibtsnicht") == nil
      assert Rankings.get_ranking_by_share_slug(nil) == nil
    end
  end

  describe "create_ranking_with_all_kits/2" do
    test "übernimmt alle Trikots der Saison in Übersichts-Reihenfolge" do
      %{season: season, kits: kits} = league_fixture(team_count: 2, kit_types: ["home", "away"])

      {:ok, ranking} = Rankings.create_ranking_with_all_kits(%{}, season)
      entries = Rankings.list_entries(ranking)

      assert length(entries) == length(kits)
      assert Enum.map(entries, & &1.position) == Enum.to_list(1..length(kits))
      assert Enum.map(entries, & &1.kit_id) == Enum.map(kits, & &1.id)
    end
  end

  describe "add_kit/2" do
    setup do
      %{kits: kits, season: season} = league_fixture(team_count: 1, kit_types: ["home", "away"])
      %{kits: kits, season: season, ranking: ranking_fixture()}
    end

    test "hängt neue Trikots hinten an", %{ranking: ranking, kits: [a, b]} do
      assert {:ok, :added} = Rankings.add_kit(ranking, a.id)
      assert {:ok, :added} = Rankings.add_kit(ranking, b.id)

      assert Rankings.list_entries(ranking) |> Enum.map(&{&1.position, &1.kit_id}) ==
               [{1, a.id}, {2, b.id}]
    end

    test "nimmt dasselbe Trikot nicht doppelt auf", %{ranking: ranking, kits: [a | _]} do
      {:ok, :added} = Rankings.add_kit(ranking, a.id)
      assert {:ok, :already_present} = Rankings.add_kit(ranking, a.id)
      assert Rankings.count_entries(ranking.id) == 1
    end

    test "lässt die vorhandene Notiz beim erneuten Hinzufügen in Ruhe", %{
      ranking: ranking,
      kits: [a | _]
    } do
      {:ok, :added} = Rankings.add_kit(ranking, a.id)
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(ranking.id, 1), "wichtig")

      {:ok, :already_present} = Rankings.add_kit(ranking, a.id)
      assert Rankings.get_entry_at(ranking.id, 1).note == "wichtig"
    end

    test "ignoriert Trikots, die es nicht gibt", %{ranking: ranking} do
      assert {:ok, :already_present} = Rankings.add_kit(ranking, 999_999)
      assert Rankings.count_entries(ranking.id) == 0
    end
  end

  describe "reorder/2" do
    setup do
      %{kits: kits} = league_fixture(team_count: 2, kit_types: ["home", "away"])
      %{kits: kits, ranking: ranking_with_kits_fixture(kits)}
    end

    test "schreibt die neue Reihenfolge", %{ranking: ranking, kits: kits} do
      reversed = kits |> Enum.map(& &1.id) |> Enum.reverse()

      assert :ok = Rankings.reorder(ranking, reversed)
      assert Rankings.list_entries(ranking) |> Enum.map(& &1.kit_id) == reversed
    end

    test "weist unvollständige Reihenfolgen zurück", %{ranking: ranking, kits: [a | _]} do
      assert {:error, :kit_ids_mismatch} = Rankings.reorder(ranking, [a.id])
    end

    test "weist fremde Trikots zurück", %{ranking: ranking, kits: kits} do
      fremd = kit_fixture()
      ids = kits |> Enum.map(& &1.id) |> Enum.drop(1)

      assert {:error, :kit_ids_mismatch} = Rankings.reorder(ranking, [fremd.id | ids])
    end

    test "lässt bei abgelehnter Reihenfolge die alte unverändert", %{
      ranking: ranking,
      kits: [a | _] = kits
    } do
      vorher = Rankings.list_entries(ranking) |> Enum.map(& &1.kit_id)
      {:error, :kit_ids_mismatch} = Rankings.reorder(ranking, [a.id])

      assert Rankings.list_entries(ranking) |> Enum.map(& &1.kit_id) == vorher
      assert length(vorher) == length(kits)
    end
  end

  describe "move_to/3" do
    setup do
      %{kits: [a, b, c] = kits} = league_fixture(team_count: 3, kit_types: ["home"])
      %{ranking: ranking_with_kits_fixture(kits), a: a, b: b, c: c}
    end

    defp reihenfolge(ranking) do
      Rankings.list_entries(ranking) |> Enum.map(& &1.kit_id)
    end

    test "setzt einen Eintrag auf den genannten Platz", %{ranking: r, a: a, b: b, c: c} do
      assert :ok = Rankings.move_to(r, c.id, 1)
      assert reihenfolge(r) == [c.id, a.id, b.id]
    end

    test "zaehlt ab 1, nicht ab 0", %{ranking: r, a: a, b: b, c: c} do
      assert :ok = Rankings.move_to(r, a.id, 2)
      assert reihenfolge(r) == [b.id, a.id, c.id]
    end

    test "haelt die Positionen luecken- und doppelfrei", %{ranking: r, c: c} do
      :ok = Rankings.move_to(r, c.id, 1)

      assert Rankings.list_entries(r) |> Enum.map(& &1.position) == [1, 2, 3]
    end

    test "eine zu grosse Zahl heisst ans Ende", %{ranking: r, a: a, b: b, c: c} do
      assert :ok = Rankings.move_to(r, a.id, 99)
      assert reihenfolge(r) == [b.id, c.id, a.id]
    end

    test "eine zu kleine Zahl heisst an den Anfang", %{ranking: r, a: a, b: b, c: c} do
      assert :ok = Rankings.move_to(r, c.id, 0)
      assert reihenfolge(r) == [c.id, a.id, b.id]

      assert :ok = Rankings.move_to(r, b.id, -5)
      assert reihenfolge(r) == [b.id, c.id, a.id]
    end

    test "der eigene Platz aendert nichts", %{ranking: r, a: a, b: b, c: c} do
      assert :ok = Rankings.move_to(r, b.id, 2)
      assert reihenfolge(r) == [a.id, b.id, c.id]
    end

    test "ein fremdes Trikot ist ein Fehler, kein stiller Umbau", %{ranking: r, a: a, b: b, c: c} do
      %{kits: [fremd]} = league_fixture(team_count: 1, kit_types: ["home"])

      assert {:error, :not_found} = Rankings.move_to(r, fremd.id, 1)
      assert reihenfolge(r) == [a.id, b.id, c.id]
    end
  end

  describe "remove_entry/1" do
    test "schließt die entstehende Lücke in den Positionen" do
      %{kits: [a, b, c]} = league_fixture(team_count: 3, kit_types: ["home"])
      ranking = ranking_with_kits_fixture([a, b, c])

      {:ok, _} = Rankings.remove_entry(Rankings.get_entry_at(ranking.id, 2))

      assert Rankings.list_entries(ranking) |> Enum.map(&{&1.position, &1.kit_id}) ==
               [{1, a.id}, {2, c.id}]
    end
  end

  describe "update_note/2" do
    setup do
      %{kits: [kit]} = league_fixture(team_count: 1, kit_types: ["home"])
      %{ranking: ranking_with_kits_fixture([kit])}
    end

    test "speichert die Notiz", %{ranking: ranking} do
      entry = Rankings.get_entry_at(ranking.id, 1)
      {:ok, entry} = Rankings.update_note(entry, "sieht komisch aus")
      assert entry.note == "sieht komisch aus"
    end

    test "behandelt eine leere Eingabe als 'keine Notiz'", %{ranking: ranking} do
      entry = Rankings.get_entry_at(ranking.id, 1)
      {:ok, entry} = Rankings.update_note(entry, "erst was")
      {:ok, entry} = Rankings.update_note(entry, "   ")

      assert entry.note == nil
    end

    test "begrenzt die Länge", %{ranking: ranking} do
      entry = Rankings.get_entry_at(ranking.id, 1)
      assert {:error, changeset} = Rankings.update_note(entry, String.duplicate("x", 501))
      assert changeset.errors[:note]
    end
  end

  describe "get_entry_at/2" do
    test "liefert nil jenseits des letzten Rangs" do
      %{kits: [kit]} = league_fixture(team_count: 1, kit_types: ["home"])
      ranking = ranking_with_kits_fixture([kit])

      assert Rankings.get_entry_at(ranking.id, 1).kit_id == kit.id
      assert Rankings.get_entry_at(ranking.id, 2) == nil
    end
  end

  test "das Löschen einer Rangliste nimmt ihre Einträge mit" do
    %{kits: kits} = league_fixture(team_count: 1, kit_types: ["home"])
    ranking = ranking_with_kits_fixture(kits)

    {:ok, _} = Rankings.delete_ranking(ranking)
    assert Rankings.count_entries(ranking.id) == 0
  end
end
