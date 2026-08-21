defmodule Kitrank.Kits.SeasonTest do
  use ExUnit.Case, async: true

  alias Kitrank.Kits.Season

  describe "parse/1" do
    test "zerlegt eine gültige Saison" do
      assert Season.parse("2026/27") == {:ok, {2026, 2027}}
    end

    test "kommt über den Jahrhundertwechsel" do
      assert Season.parse("2099/00") == {:ok, {2099, 2100}}
    end

    test "lehnt falsches Format ab" do
      assert Season.parse("2026-27") == :error
      assert Season.parse("26/27") == :error
      assert Season.parse("2026/2027") == :error
      assert Season.parse(nil) == :error
    end

    test "lehnt nicht aufeinanderfolgende Jahre ab" do
      assert Season.parse("2026/28") == :error
      assert Season.parse("2026/25") == :error
    end
  end

  describe "from_start_year/1" do
    test "füllt einstellige Endjahre auf" do
      assert Season.from_start_year(2008) == "2008/09"
      assert Season.from_start_year(2026) == "2026/27"
      assert Season.from_start_year(2099) == "2099/00"
    end
  end

  describe "current/1" do
    test "wechselt zum 1. Juli auf die neue Saison" do
      assert Season.current(~D[2026-06-30]) == "2025/26"
      assert Season.current(~D[2026-07-01]) == "2026/27"
      assert Season.current(~D[2026-12-31]) == "2026/27"
      assert Season.current(~D[2027-01-15]) == "2026/27"
    end
  end
end
