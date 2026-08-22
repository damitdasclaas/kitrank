defmodule Kitrank.Reveal.ResultTest do
  @moduledoc """
  Die Auswertung soll Reibung zeigen, nicht Durchschnitte glätten. Geprüft wird
  mit von Hand gesetzten Ranglisten, bei denen man das Ergebnis vorher weiß.
  """
  use ExUnit.Case, async: true

  alias Kitrank.Reveal.Result

  # Minimale Attrappen: die Auswertung braucht nur kit_id, note und ein kit.
  defp eintrag(kit_id, note \\ nil) do
    %{kit_id: kit_id, note: note, kit: %{id: kit_id}}
  end

  defp person(id, name), do: %{id: id, display_name: name}

  describe "Einigkeit und Streit" do
    setup do
      tom = person(1, "Tom")
      anna = person(2, "Anna")

      # Tom und Anna sind sich bei A einig, bei D maximal uneins.
      %{
        participants: [tom, anna],
        entries: %{
          1 => [eintrag(:a), eintrag(:b), eintrag(:c), eintrag(:d)],
          2 => [eintrag(:a), eintrag(:c), eintrag(:b), eintrag(:d)]
        }
      }
    end

    test "sortiert nach mittlerer Platzierung", %{participants: p, entries: e} do
      auswertung = Result.build(p, e)

      ids = Enum.map(auswertung.kits, & &1.kit_id)

      # b und c haben denselben Mittelwert (2,5) – ein echter Gleichstand.
      # Feststehen muss, dass a vorn und d hinten landet.
      assert List.first(ids) == :a
      assert List.last(ids) == :d
      assert Enum.sort(ids) == [:a, :b, :c, :d]
      assert hd(auswertung.kits).average == 1.0
    end

    test "sortiert bei Gleichstand nach Einigkeit" do
      # x und y haben denselben Mittelwert; bei x sind sich alle einig.
      auswertung =
        Result.build([person(1, "Tom"), person(2, "Anna")], %{
          1 => [eintrag(:x), eintrag(:y), eintrag(:z)],
          2 => [eintrag(:x), eintrag(:z), eintrag(:y)]
        })

      # y: 2 und 3 -> 2,5 / z: 3 und 2 -> 2,5, Streuung bei beiden 1
      # x: 1 und 1 -> 1,0, Streuung 0 -> muss vorn stehen
      assert hd(auswertung.kits).kit_id == :x
      assert hd(auswertung.kits).spread == 0
    end

    test "findet den größten Streitfall" do
      tom = person(1, "Tom")
      anna = person(2, "Anna")

      auswertung =
        Result.build([tom, anna], %{
          1 => [eintrag(:streit), eintrag(:x), eintrag(:y)],
          2 => [eintrag(:x), eintrag(:y), eintrag(:streit)]
        })

      assert auswertung.biggest_split.kit_id == :streit
      assert auswertung.biggest_split.spread == 2
      # Und wer es wo hatte – das ist die Zeile, die man weiterschickt.
      assert [%{participant_name: "Tom", position: 1}, %{participant_name: "Anna", position: 3}] =
               auswertung.biggest_split.positions
    end

    test "meldet gemeinsame Spitze und gemeinsames Schlusslicht", %{participants: p, entries: e} do
      auswertung = Result.build(p, e)

      assert hd(auswertung.consensus_top).kit_id == :a
      assert hd(auswertung.consensus_bottom).kit_id == :d
    end

    test "misst den Abstand zwischen zwei Personen", %{participants: p, entries: e} do
      auswertung = Result.build(p, e)

      assert [paar] = auswertung.pairs
      assert paar.a == "Tom" and paar.b == "Anna"
      # b und c sind je einen Platz verschoben, a und d gleich: 2/4 = 0.5
      assert paar.distance == 0.5
    end

    test "identische Ranglisten haben Abstand null" do
      liste = [eintrag(:a), eintrag(:b), eintrag(:c)]

      auswertung =
        Result.build([person(1, "Tom"), person(2, "Anna")], %{1 => liste, 2 => liste})

      assert [%{distance: +0.0}] = auswertung.pairs
      assert auswertung.biggest_split.spread == 0
    end
  end

  describe "Nur was alle bewertet haben" do
    test "ignoriert Trikots, die nicht in jeder Liste stehen" do
      auswertung =
        Result.build([person(1, "Tom"), person(2, "Anna")], %{
          1 => [eintrag(:gemeinsam), eintrag(:nur_tom)],
          2 => [eintrag(:gemeinsam), eintrag(:nur_anna)]
        })

      # Sonst haette ein Trikot, das nur einer kennt, automatisch die groesste
      # Einigkeit.
      assert Enum.map(auswertung.kits, & &1.kit_id) == [:gemeinsam]
      assert auswertung.shared_count == 1
    end

    test "kommt mit gar keiner Überschneidung klar" do
      auswertung =
        Result.build([person(1, "Tom"), person(2, "Anna")], %{
          1 => [eintrag(:a)],
          2 => [eintrag(:b)]
        })

      assert auswertung.shared_count == 0
      assert auswertung.kits == []
      assert auswertung.biggest_split == nil
      assert auswertung.pairs == []
    end
  end

  describe "Notizen" do
    test "sammelt sie mit Person und Platz" do
      auswertung =
        Result.build([person(1, "Tom"), person(2, "Anna")], %{
          1 => [eintrag(:a, "grausam"), eintrag(:b)],
          2 => [eintrag(:b), eintrag(:a, "  finde ich schön  ")]
        })

      assert length(auswertung.notes) == 2
      assert %{participant_name: "Tom", position: 1, note: "grausam"} = hd(auswertung.notes)
      # Leerraum wird getrimmt, leere Notizen fallen weg.
      assert Enum.any?(auswertung.notes, &(&1.note == "finde ich schön"))
    end

    test "lässt leere Notizen weg" do
      auswertung =
        Result.build([person(1, "Tom")], %{1 => [eintrag(:a, "   "), eintrag(:b, nil)]})

      assert auswertung.notes == []
    end
  end

  describe "Randfälle" do
    test "eine Person allein hat keine Paare" do
      auswertung = Result.build([person(1, "Tom")], %{1 => [eintrag(:a), eintrag(:b)]})

      assert auswertung.pairs == []
      assert auswertung.shared_count == 2
      assert auswertung.biggest_split.spread == 0
    end

    test "niemand im Raum" do
      auswertung = Result.build([], %{})

      assert auswertung.kits == []
      assert auswertung.shared_count == 0
      assert auswertung.notes == []
    end
  end
end
