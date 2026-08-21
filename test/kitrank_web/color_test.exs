defmodule KitrankWeb.ColorTest do
  use ExUnit.Case, async: true

  alias KitrankWeb.Color

  describe "readable_on/1" do
    test "wählt dunkle Schrift auf hellen Vereinsfarben" do
      # Dortmund-Gelb und Weiß – hier waere heller Text unlesbar.
      assert Color.readable_on("#FDE100") == "#131815"
      assert Color.readable_on("#FFFFFF") == "#131815"
    end

    test "wählt helle Schrift auf dunklen Vereinsfarben" do
      assert Color.readable_on("#000000") == "#F5F7F3"
      assert Color.readable_on("#004D9D") == "#F5F7F3"
    end
  end

  describe "luminance/1" do
    test "liegt zwischen Schwarz und Weiß" do
      assert Color.luminance("#000000") == 0.0
      assert_in_delta Color.luminance("#FFFFFF"), 1.0, 0.001
      assert Color.luminance("#DC052D") < Color.luminance("#FDE100")
    end
  end

  describe "contrast_shade/1" do
    test "dunkelt helle Farben ab und hellt dunkle auf" do
      assert Color.luminance(Color.contrast_shade("#FDE100")) < Color.luminance("#FDE100")
      assert Color.luminance(Color.contrast_shade("#000000")) > Color.luminance("#000000")
    end

    test "bleibt auch bei Schwarz und Weiß sichtbar" do
      refute Color.contrast_shade("#000000") == "#000000"
      refute Color.contrast_shade("#FFFFFF") == "#FFFFFF"
    end
  end

  describe "on_dark/1" do
    test "hellt jede Vereinsfarbe so weit auf, dass sie auf dunklem Grund trägt" do
      # Schwarz und Dunkelblau sind die Faelle, an denen ein fester Aufhell-Wert
      # scheitern wuerde.
      for color <- ["#000000", "#005CA9", "#DC052D", "#1D9053", "#6B4423"] do
        assert Color.luminance(Color.on_dark(color)) >= 0.45,
               "#{color} bleibt zu dunkel: #{Color.on_dark(color)}"
      end
    end

    test "lässt schon helle Farben in Ruhe" do
      assert Color.on_dark("#FDE100") == "#FDE100"
      assert Color.on_dark("#FFFFFF") == "#FFFFFF"
    end
  end

  describe "team_color/1" do
    test "nutzt die Vereinsfarbe, wenn es eine gibt" do
      assert Color.team_color(%{primary_color: "#DC052D"}) == "#DC052D"
    end

    test "fällt auf einen neutralen Ton zurück, wenn keine gepflegt ist" do
      assert Color.team_color(%{primary_color: nil}) == "#7A847D"
    end
  end

  describe "mix/3" do
    test "mischt zwischen zwei Farben" do
      assert Color.mix("#000000", "#FFFFFF", 0.0) == "#000000"
      assert Color.mix("#000000", "#FFFFFF", 1.0) == "#FFFFFF"
      assert Color.mix("#000000", "#FFFFFF", 0.5) == "#808080"
    end
  end

  test "kommt mit Kurzform und Unsinn klar, ohne zu crashen" do
    assert Color.luminance("#fff") > 0.9
    assert is_binary(Color.mix("keine-farbe", "#FFFFFF", 0.5))
  end
end
