defmodule Kitrank.Kits.Import do
  @moduledoc """
  Stammdaten einer Saison aus einer Datei einspielen: Sportart, Ligen, Vereine
  und wer in welcher Liga spielt.

  Warum als Datei und nicht über die Admin-UI: 36 Vereine von Hand einzutragen
  ist einmal mühsam und jedes Jahr wieder mühsam. Die Datei liegt in Git, lässt
  sich für die nächste Saison kopieren, und Auf-/Abstiege sind dann drei
  geänderte Zeilen statt einer Klickstrecke.

  **Trikot-Bilder** gehören bewusst nicht hierher: sie ändern sich laufend,
  sehen bei jedem Verein anders aus und brauchen ein Auge — die pflegst du über
  `/admin`.

  Die leeren **Trikot-Datensätze** legt der Import dagegen an (`kit_types` in
  der Datei). Ohne sie hätte ein frisch importierter Verein gar kein Trikot,
  und die Übersicht könnte auch nichts zeichnen — die gezeichnete Darstellung
  ist der Ersatz für ein Trikot ohne Bild, nicht für einen Verein ohne Trikot.

  Der Import ist idempotent: mehrfaches Ausführen legt nichts doppelt an und
  überschreibt nur, was sich geändert hat.
  """

  alias Kitrank.Kits
  alias Kitrank.Kits.{Competition, Kit, Team, TeamSeason}
  alias Kitrank.Repo

  @default_file "data/teams_2026_27.json"

  @doc """
  Spielt die mitgelieferte Datei ein, oder eine andere per Pfad.

  Gibt `{:ok, bericht}` zurück – der Bericht sagt, was neu ist und was
  aktualisiert wurde, damit man nach dem Lauf sieht, ob es das war, was man
  wollte.
  """
  def run(path \\ nil) do
    path = path || Path.join(:code.priv_dir(:kitrank), @default_file)

    with {:ok, raw} <- File.read(path),
         {:ok, data} <- decode(raw) do
      Repo.transaction(fn -> import_data(data) end)
    else
      {:error, :enoent} -> {:error, "Datei nicht gefunden: #{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(raw) do
    case JSON.decode(raw) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "Datei ist kein gültiges JSON: #{inspect(reason)}"}
    end
  end

  defp import_data(%{"season" => season, "sport" => sport, "competitions" => competitions} = data) do
    sport = upsert_sport(sport)
    kit_types = Map.get(data, "kit_types", [])

    bericht =
      Enum.reduce(competitions, blank_report(season), fn attrs, bericht ->
        competition = upsert_competition(sport, attrs)

        Enum.reduce(attrs["teams"], bericht, fn team_attrs, bericht ->
          {team, team_status} = upsert_team(team_attrs)
          season_status = upsert_team_season(team, competition, season)

          bericht
          |> count(:teams, team_status)
          |> count(:zuordnungen, season_status)
          |> Map.update!(:trikots, &(&1 + ensure_kits(team, season, kit_types)))
        end)
        |> Map.update!(:ligen, &(&1 + 1))
      end)

    # Was in dieser Saison noch zugeordnet ist, aber nicht mehr in der Datei
    # steht, ist abgestiegen oder aufgestiegen – und gehoert nicht mehr hierher.
    verwaist = remove_stale(season, competitions)

    Map.put(bericht, :entfernt, verwaist)
  end

  defp import_data(_other) do
    Repo.rollback("Datei braucht die Schlüssel season, sport und competitions")
  end

  defp blank_report(season) do
    %{
      season: season,
      ligen: 0,
      teams: %{neu: 0, geaendert: 0, unveraendert: 0},
      zuordnungen: %{neu: 0, geaendert: 0, unveraendert: 0},
      trikots: 0,
      entfernt: 0
    }
  end

  # Legt fehlende Trikot-Datensaetze an und ruehrt vorhandene nicht an – sonst
  # waeren mit jedem Import die im Admin gepflegten Bilder weg.
  defp ensure_kits(team, season, kit_types) do
    Enum.count(kit_types, fn kit_type ->
      case Repo.get_by(Kit, team_id: team.id, season: season, kit_type: kit_type) do
        nil ->
          insert!(Kits.create_kit(%{team_id: team.id, season: season, kit_type: kit_type}))
          true

        _vorhanden ->
          false
      end
    end)
  end

  defp count(bericht, schluessel, status) do
    Map.update!(bericht, schluessel, &Map.update!(&1, status, fn n -> n + 1 end))
  end

  defp upsert_sport(%{"slug" => slug} = attrs) do
    case Kits.get_sport_by_slug(slug) do
      nil -> insert!(Kits.create_sport(attrs))
      sport -> sport
    end
  end

  defp upsert_competition(sport, attrs) do
    attrs = Map.take(attrs, ["name", "country", "tier"]) |> Map.put("sport_id", sport.id)

    case Repo.get_by(Competition,
           sport_id: sport.id,
           country: attrs["country"],
           name: attrs["name"]
         ) do
      nil -> insert!(Kits.create_competition(attrs))
      competition -> insert!(Kits.update_competition(competition, attrs))
    end
  end

  defp upsert_team(attrs) do
    attrs = Map.take(attrs, ["name", "short_code", "primary_color", "shop_url"])

    case Repo.get_by(Team, short_code: String.upcase(attrs["short_code"])) do
      nil ->
        {insert!(Kits.create_team(attrs)), :neu}

      team ->
        # shop_url wird ueber /admin gepflegt – ein leerer Wert in der Datei
        # soll ihn nicht wieder loeschen.
        attrs = if is_nil(attrs["shop_url"]), do: Map.delete(attrs, "shop_url"), else: attrs
        changeset = Team.changeset(team, attrs)
        status = if changeset.changes == %{}, do: :unveraendert, else: :geaendert

        {insert!(Repo.update(changeset)), status}
    end
  end

  defp upsert_team_season(team, competition, season) do
    case Repo.get_by(TeamSeason, team_id: team.id, season: season) do
      nil ->
        insert!(
          Kits.create_team_season(%{
            team_id: team.id,
            competition_id: competition.id,
            season: season
          })
        )

        :neu

      %{competition_id: id} when id == competition.id ->
        :unveraendert

      team_season ->
        insert!(Kits.update_team_season(team_season, %{competition_id: competition.id}))
        :geaendert
    end
  end

  # Zuordnungen dieser Saison, die es in der Datei nicht mehr gibt. Die Vereine
  # selbst bleiben stehen – ihre Trikots aus frueheren Saisons sollen nicht
  # verschwinden, nur weil sie abgestiegen sind.
  defp remove_stale(season, competitions) do
    gueltig =
      for competition <- competitions,
          team <- competition["teams"],
          into: MapSet.new(),
          do: String.upcase(team["short_code"])

    season
    |> Kits.list_team_seasons()
    |> Enum.reject(&MapSet.member?(gueltig, &1.team.short_code))
    |> Enum.map(&insert!(Kits.delete_team_season(&1)))
    |> length()
  end

  defp insert!({:ok, record}), do: record

  defp insert!({:error, %Ecto.Changeset{} = changeset}) do
    Repo.rollback(fehler_text(changeset))
  end

  defp fehler_text(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {feld, msgs} -> "#{feld}: #{Enum.join(msgs, ", ")}" end)
    |> then(&"#{inspect(changeset.data.__struct__)} — #{&1}")
  end

  @doc "Bericht als lesbarer Text für die Konsole."
  def format(%{} = b) do
    """
    Saison #{b.season}
      Ligen:       #{b.ligen}
      Vereine:     #{b.teams.neu} neu, #{b.teams.geaendert} geändert, #{b.teams.unveraendert} unverändert
      Zuordnungen: #{b.zuordnungen.neu} neu, #{b.zuordnungen.geaendert} geändert, #{b.zuordnungen.unveraendert} unverändert
      Trikots:     #{b.trikots} leere angelegt (vorhandene unangetastet)
      Entfernt:    #{b.entfernt} Zuordnung(en), die nicht mehr in der Datei stehen

    Bilder und Shop-Deep-Links pflegst du über /admin.
    """
  end
end
