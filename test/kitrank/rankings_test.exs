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

  describe "Ausschnitt" do
    setup do
      %{teams: [a, b], kits: kits} = league_fixture(team_count: 2, kit_types: ["home", "away"])
      {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})
      %{ranking: ranking, a: a, b: b, kits: kits}
    end

    test "eine frische Rangliste schränkt nichts ein", %{ranking: ranking} do
      # Leer heisst „alles" – und fuer Ranglisten von vor der Speicherung ist
      # das der ehrlichste Ersatz fuer „wir wissen es nicht mehr".
      assert Kitrank.Kits.Scope.empty?(Rankings.Ranking.scope(ranking))
    end

    test "der Ausschnitt übersteht einen Neustart", %{ranking: ranking, a: a} do
      # Vorher war er fluechtig: beim Laden aus den Eintraegen erraten, Tab zu,
      # Einstellungen weg.
      {:ok, _} =
        Rankings.update_scope(ranking, %{
          seasons: [Kitrank.Kits.current_season()],
          team_ids: [a.id],
          kit_types: ["away"]
        })

      frisch = Rankings.get_ranking_by_edit_token(ranking.edit_token)
      scope = Rankings.Ranking.scope(frisch)

      assert scope.seasons == [Kitrank.Kits.current_season()]
      assert scope.team_ids == [a.id]
      assert scope.kit_types == ["away"]
    end

    test "die Trikot-Typ-Achse grenzt wirklich ein", %{ranking: ranking} do
      # Die Luecke, die dabei aufgefallen ist: „alle Auswaertstrikots dieser
      # vier Vereine" liess sich vorher gar nicht ausdruecken.
      alle = Rankings.kits_in_scope(ranking)

      {:ok, ranking} = Rankings.update_scope(ranking, %{kit_types: ["away"]})
      nur_auswaerts = Rankings.kits_in_scope(ranking)

      assert length(alle) == 4
      assert length(nur_auswaerts) == 2
      assert Enum.all?(nur_auswaerts, &(&1.kit.kit_type == "away"))
    end

    test "Verein und Typ greifen zusammen", %{ranking: ranking, a: a} do
      {:ok, ranking} = Rankings.update_scope(ranking, %{team_ids: [a.id], kit_types: ["away"]})

      assert [%{kit: kit}] = Rankings.kits_in_scope(ranking)
      assert kit.team_id == a.id
      assert kit.kit_type == "away"
    end

    test "ein erfundener Trikot-Typ wird abgelehnt", %{ranking: ranking} do
      assert {:error, changeset} =
               Rankings.update_ranking(ranking, %{scope_kit_types: ["throwback"]})

      assert %{scope_kit_types: _} = errors_on(changeset)
    end
  end

  describe "Teilen mit Gate" do
    setup do
      %{teams: [a, _b], kits: kits} = league_fixture(team_count: 2, kit_types: ["home"])
      {:ok, original} = Rankings.create_ranking(%{display_name: "Toms Liste"})

      {:ok, original} =
        Rankings.update_scope(original, %{seasons: [Kitrank.Kits.current_season()]})

      %{original: original, kits: kits, a: a}
    end

    test "eine Rangliste ist zunächst offen", %{original: original} do
      refute Rankings.Ranking.gated?(original)
    end

    test "abgeleitet heißt: derselbe Ausschnitt", %{original: original, a: a} do
      {:ok, original} = Rankings.update_scope(original, %{team_ids: [a.id], kit_types: ["home"]})
      {:ok, eigene} = Rankings.create_derived(original)

      assert eigene.derived_from_id == original.id

      assert Kitrank.Kits.Scope.same?(
               Rankings.Ranking.scope(eigene),
               Rankings.Ranking.scope(original)
             )
    end

    test "vollständig heißt: jedes Trikot des Ausschnitts hat einen Platz", %{
      original: original,
      kits: kits
    } do
      # Eine halbe Liste zu akzeptieren wuerde die Regel aushoehlen.
      {:ok, eigene} = Rankings.create_derived(original)
      refute Rankings.complete?(eigene)

      Rankings.add_kit(eigene, hd(kits).id)
      refute Rankings.complete?(eigene)

      Rankings.add_kits(eigene, Enum.map(kits, & &1.id))
      assert Rankings.complete?(eigene)
    end

    test "ohne eigene Liste kommt niemand durch", %{original: original} do
      assert Rankings.gate_state(original, []) == :none
      assert Rankings.gate_state(original, ["erfunden"]) == :none
    end

    test "eine fremde Liste zählt nicht", %{original: original} do
      # Irgendeine Rangliste im Browser reicht nicht – sie muss von dieser
      # abgeleitet sein.
      {:ok, fremde} = Rankings.create_ranking(%{display_name: "Was anderes"})

      assert Rankings.gate_state(original, [fremde.edit_token]) == :none
    end

    test "eine angefangene meldet sich als angefangen", %{original: original, kits: kits} do
      {:ok, eigene} = Rankings.create_derived(original)
      Rankings.add_kit(eigene, hd(kits).id)

      assert {:building, gefunden} = Rankings.gate_state(original, [eigene.edit_token])
      assert gefunden.id == eigene.id
    end

    test "eine fertige öffnet das Gate", %{original: original, kits: kits} do
      {:ok, eigene} = Rankings.create_derived(original)
      Rankings.add_kits(eigene, Enum.map(kits, & &1.id))

      assert {:passed, gefunden} = Rankings.gate_state(original, [eigene.edit_token])
      assert gefunden.id == eigene.id
    end

    test "ein nachträglich geänderter Ausschnitt schließt es wieder", %{
      original: original,
      kits: kits,
      a: a
    } do
      # Sonst wuerde eine geaenderte Einstellung den Vergleich still entwerten:
      # zwei Listen ueber verschiedene Trikots vergleichen sich nicht.
      {:ok, eigene} = Rankings.create_derived(original)
      Rankings.add_kits(eigene, Enum.map(kits, & &1.id))
      assert {:passed, _} = Rankings.gate_state(original, [eigene.edit_token])

      {:ok, _} = Rankings.update_scope(eigene, %{team_ids: [a.id]})

      assert Rankings.gate_state(original, [eigene.edit_token]) == :none
    end

    test "der Teilen-Modus lässt sich setzen und nur auf gültige Werte", %{original: original} do
      assert {:ok, %{share_mode: "gated"}} = Rankings.set_share_mode(original, "gated")
      assert {:ok, %{share_mode: "open"}} = Rankings.set_share_mode(original, "open")
      assert {:error, changeset} = Rankings.set_share_mode(original, "irgendwas")
      assert %{share_mode: _} = errors_on(changeset)
    end

    test "verschwindet das Original, bleibt die eigene Liste", %{original: original} do
      # Sie gehoert jemand anderem.
      {:ok, eigene} = Rankings.create_derived(original)
      {:ok, _} = Rankings.delete_ranking(original)

      frisch = Rankings.get_ranking_by_edit_token(eigene.edit_token)
      assert frisch
      assert is_nil(frisch.derived_from_id)
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
