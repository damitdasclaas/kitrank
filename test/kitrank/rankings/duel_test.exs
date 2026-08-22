defmodule Kitrank.Rankings.DuelTest do
  @moduledoc """
  Das Verfahren muss zwei Dinge leisten: am Ende korrekt sortieren, und
  zwischendurch jederzeit eine brauchbare Reihenfolge liefern.

  Geprüft wird gegen eine bekannte Wunschordnung — ein "Vergleicher", der immer
  weiß, was besser ist. Kommt am Ende genau diese Ordnung heraus, stimmt das
  Verfahren.
  """
  use ExUnit.Case, async: true

  alias Kitrank.Rankings.Duel

  # Beantwortet Fragen so, als waere `wunsch` die Wahrheit.
  defp durchspielen(state, wunsch) do
    case Duel.question(state) do
      :done ->
        state

      {neu, alt} ->
        wahl =
          if Enum.find_index(wunsch, &(&1 == neu)) < Enum.find_index(wunsch, &(&1 == alt)),
            do: :new,
            else: :existing

        state |> Duel.answer(wahl) |> durchspielen(wunsch)
    end
  end

  describe "sortiert korrekt" do
    test "bei umgekehrter Ausgangsreihenfolge" do
      wunsch = Enum.to_list(1..10)
      state = Duel.start(Enum.reverse(wunsch))

      assert Duel.order(durchspielen(state, wunsch)) == wunsch
    end

    test "bei zufälligen Ausgangsreihenfolgen" do
      wunsch = Enum.to_list(1..12)

      for _ <- 1..25 do
        start = Duel.start(Enum.shuffle(wunsch))
        assert Duel.order(durchspielen(start, wunsch)) == wunsch
      end
    end

    test "wenn die Ausgangsreihenfolge schon stimmt" do
      wunsch = Enum.to_list(1..8)
      fertig = durchspielen(Duel.start(wunsch), wunsch)

      assert Duel.order(fertig) == wunsch
    end
  end

  describe "Anzahl der Fragen" do
    test "bleibt in der Größenordnung n·log n" do
      wunsch = Enum.to_list(1..20)
      fertig = durchspielen(Duel.start(Enum.shuffle(wunsch)), wunsch)

      # Untere Grenze der Informationstheorie ist log2(20!) ≈ 61; jeder gegen
      # jeden waeren 190.
      assert fertig.comparisons <= 90, "#{fertig.comparisons} Fragen sind zu viele"
      assert fertig.comparisons >= 40
    end

    test "zählt jede Antwort" do
      state = Duel.start([1, 2, 3])
      assert Duel.progress(state).comparisons == 0

      state = Duel.answer(state, :new)
      assert Duel.progress(state).comparisons == 1
    end
  end

  describe "Zwischenstand" do
    test "ist jederzeit eine vollständige Reihenfolge" do
      wunsch = Enum.to_list(1..9)
      state = Duel.start(Enum.shuffle(wunsch))

      state =
        Enum.reduce(1..6, state, fn _, acc ->
          case Duel.question(acc) do
            :done -> acc
            {_neu, _alt} -> Duel.answer(acc, :new)
          end
        end)

      # Nichts verloren, nichts doppelt – abbrechen ist also gefahrlos.
      assert Enum.sort(Duel.order(state)) == wunsch
    end

    test "meldet den Fortschritt" do
      state = Duel.start(Enum.to_list(1..10))
      fortschritt = Duel.progress(state)

      assert fortschritt.total == 10
      assert fortschritt.placed == 1
      assert fortschritt.remaining_estimate > 0
    end
  end

  describe "Randfälle" do
    test "leere Liste ist sofort fertig" do
      state = Duel.start([])

      assert Duel.done?(state)
      assert Duel.question(state) == :done
      assert Duel.order(state) == []
    end

    test "ein einzelnes Trikot braucht keinen Vergleich" do
      state = Duel.start([42])

      assert Duel.done?(state)
      assert Duel.order(state) == [42]
    end

    test "zwei Trikots brauchen genau eine Frage" do
      state = Duel.start([1, 2])
      assert {2, 1} = Duel.question(state)

      fertig = Duel.answer(state, :new)
      assert Duel.done?(fertig)
      assert Duel.order(fertig) == [2, 1]
      assert fertig.comparisons == 1
    end

    test "wirft Duplikate weg" do
      state = Duel.start([1, 1, 2, 2, 3])
      assert Enum.sort(Duel.order(state)) == [1, 2, 3]
    end

    test "eine Antwort nach dem Ende ändert nichts" do
      fertig = Duel.start([1])

      assert Duel.answer(fertig, :new) == fertig
    end
  end
end
