defmodule Kitrank.KitsFixtures do
  @moduledoc """
  Testdaten für den Kits-Context.

  `league_fixture/1` baut die komplette Kette Sport → Competition → Team →
  TeamSeason → Kits auf, weil ein Trikot ohne diese Kette in keiner Query auftaucht.
  """

  alias Kitrank.Kits

  @doc """
  Ein Kürzel, das in die erlaubten fünf Zeichen passt und trotzdem eindeutig
  bleibt.

  Die laufende Nummer einfach abzuschneiden reicht nicht: sobald sie vierstellig
  wird, wiederholen sich die Kürzel, der Unique-Index schlägt zu, und es stirbt
  irgendein Test – je nach Reihenfolge ein anderer. Base36 bringt vier Stellen
  auf 1.679.616 Werte unter.
  """
  def unique_short_code do
    laufend = System.unique_integer([:positive]) |> rem(1_679_616)

    "T" <> (laufend |> Integer.to_string(36) |> String.pad_leading(4, "0"))
  end

  def sport_fixture(attrs \\ %{}) do
    {:ok, sport} =
      attrs
      |> Enum.into(%{name: "Fußball", slug: "football-#{System.unique_integer([:positive])}"})
      |> Kits.create_sport()

    sport
  end

  def competition_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    sport_id = Map.get_lazy(attrs, :sport_id, fn -> sport_fixture().id end)

    {:ok, competition} =
      attrs
      |> Enum.into(%{
        sport_id: sport_id,
        name: "Bundesliga #{System.unique_integer([:positive])}",
        country: "DE",
        tier: 1
      })
      |> Kits.create_competition()

    competition
  end

  def team_fixture(attrs \\ %{}) do
    {:ok, team} =
      attrs
      |> Enum.into(%{
        name: "Testverein #{System.unique_integer([:positive])}",
        short_code: unique_short_code(),
        primary_color: "#DC052D"
      })
      |> Kits.create_team()

    team
  end

  def kit_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    team_id = Map.get_lazy(attrs, :team_id, fn -> team_fixture().id end)

    {:ok, kit} =
      attrs
      |> Enum.into(%{
        team_id: team_id,
        season: Kits.current_season(),
        kit_type: "home"
      })
      |> Kits.create_kit()

    kit
  end

  @doc """
  Eine Liga mit `team_count` Teams, die je `kit_types` Trikots haben.

  Gibt `%{competition: ..., teams: [...], kits: [...]}` zurück; `kits` ist in
  Übersichts-Reihenfolge (Team, dann Kit-Typ).
  """
  def league_fixture(opts \\ []) do
    season = Keyword.get(opts, :season, Kits.current_season())
    team_count = Keyword.get(opts, :team_count, 2)
    kit_types = Keyword.get(opts, :kit_types, ["home", "away"])

    competition =
      Keyword.get_lazy(opts, :competition, fn ->
        competition_fixture(tier: Keyword.get(opts, :tier, 1))
      end)

    teams =
      for i <- 1..team_count do
        # Namen mit laufendem Buchstaben, damit die alphabetische Sortierung
        # in den Tests vorhersagbar ist.
        team = team_fixture(name: "#{<<64 + i>>} Verein #{System.unique_integer([:positive])}")

        {:ok, _} =
          Kits.create_team_season(%{
            team_id: team.id,
            competition_id: competition.id,
            season: season
          })

        team
      end

    kits =
      for team <- teams, kit_type <- kit_types do
        kit_fixture(team_id: team.id, season: season, kit_type: kit_type)
      end

    %{competition: competition, teams: teams, kits: kits, season: season}
  end
end
