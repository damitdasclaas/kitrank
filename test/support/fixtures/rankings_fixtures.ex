defmodule Kitrank.RankingsFixtures do
  @moduledoc "Testdaten für den Rankings-Context."

  alias Kitrank.Rankings

  def ranking_fixture(attrs \\ %{}) do
    {:ok, ranking} = attrs |> Enum.into(%{display_name: "Testliste"}) |> Rankings.create_ranking()
    ranking
  end

  @doc "Rangliste, die die übergebenen Trikots in genau dieser Reihenfolge enthält."
  def ranking_with_kits_fixture(kits, attrs \\ %{}) do
    ranking = ranking_fixture(attrs)
    Enum.each(kits, &Rankings.add_kit(ranking, &1.id))
    ranking
  end
end
