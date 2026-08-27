defmodule Kitrank.Kits.ScopeTest do
  @moduledoc """
  Der Ausschnitt gab es zweimal — als Map mit `seasons`/`team_ids` für
  Ranglisten und als Spalten `season`/`kit_types` am Reveal-Raum. Hier steht
  die eine Fassung, auf die sich beide einigen.
  """
  use ExUnit.Case, async: true

  alias Kitrank.Kits.Scope

  describe "new/1" do
    test "ohne Angabe ist alles gemeint" do
      assert Scope.empty?(Scope.new(%{}))
      assert Scope.empty?(Scope.new(nil))
      assert Scope.empty?(%Scope{})
    end

    test "nimmt Atom- und String-Schlüssel" do
      assert %Scope{seasons: ["2026/27"]} = Scope.new(%{seasons: ["2026/27"]})
      assert %Scope{seasons: ["2026/27"]} = Scope.new(%{"seasons" => ["2026/27"]})
    end

    test "nimmt MapSets, weil Formulare damit arbeiten" do
      scope = Scope.new(%{team_ids: MapSet.new([3, 1])})
      assert Enum.sort(scope.team_ids) == [1, 3]
    end

    test "nimmt einen einzelnen Wert als Liste" do
      # Der Reveal-Raum fuehrt `season` in der Einzahl.
      assert %Scope{seasons: ["2026/27"]} = Scope.new(%{seasons: "2026/27"})
    end

    test "lässt unbekannte Schlüssel weg" do
      # Der Ausschnitt kommt teils aus Formularen – was er nicht kennt, soll
      # er nicht durchreichen.
      scope = Scope.new(%{seasons: ["2026/27"], quatsch: ["x"]})

      assert scope == %Scope{seasons: ["2026/27"]}
    end

    test "ist auf sich selbst anwendbar" do
      scope = Scope.new(%{kit_types: ["away"]})
      assert Scope.new(scope) == scope
    end
  end

  describe "same?/2" do
    test "die Reihenfolge innerhalb einer Achse zählt nicht" do
      # „HSV, BVB" ist derselbe Ausschnitt wie „BVB, HSV".
      assert Scope.same?(%Scope{team_ids: [1, 2]}, %Scope{team_ids: [2, 1]})
    end

    test "eine andere Achse macht einen anderen Ausschnitt" do
      refute Scope.same?(%Scope{team_ids: [1]}, %Scope{competition_ids: [1]})
    end

    test "vergleicht auch, was erst noch einer werden muss" do
      assert Scope.same?(%{seasons: ["2026/27"]}, %Scope{seasons: ["2026/27"]})
    end
  end
end
