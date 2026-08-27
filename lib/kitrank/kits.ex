defmodule Kitrank.Kits do
  @moduledoc """
  Stammdaten: Sportarten, Wettbewerbe, Teams, Saison-Zugehörigkeiten und Trikots.

  Liefert die Daten für die Übersicht und ist gleichzeitig die Schreib-Schicht
  hinter der Admin-UI – ein eigener Admin-Context wäre nur eine Hülle um dieselben
  Funktionen.
  """

  import Ecto.Query, warn: false

  alias Kitrank.Repo
  alias Kitrank.Kits.{Competition, Kit, Scope, Season, Sport, Team, TeamSeason}

  # Sortiert Trikots nach fachlicher Reihenfolge statt alphabetisch, damit "away"
  # nicht vor "home" landet. Als Makro, weil es in mehreren Queries auftaucht.
  defmacrop kit_type_order(kit) do
    quote do
      fragment(
        "array_position(ARRAY['home','away','third','special']::varchar[], ?)",
        unquote(kit).kit_type
      )
    end
  end

  @doc "Die aktuelle Saison im Format \"2026/27\" (Stichtag 1. Juli)."
  defdelegate current_season(), to: Season, as: :current

  @doc """
  Die Reihenfolge, in der Ligen überall erscheinen: Sportart, dann Land, dann
  Spielklasse, dann Name.

  Damit stehen 1. und 2. Bundesliga beieinander. Nach `tier` allein sortiert
  schob sich die NFL als weitere Liga der Stufe 1 dazwischen — sie ist erste
  Liga, aber einer anderen Sportart und eines anderen Landes.

  Die Sportart nach `sport_id`, also in der Reihenfolge, in der sie angelegt
  wurden. Alphabetisch stünde "American Football" vor "Fußball", und jede neue
  Sportart könnte sich vor die bestehenden schieben, ohne dass jemand das
  entschieden hätte. Wer die Reihenfolge frei bestimmen will, braucht eine
  Spalte dafür.

  Braucht die Liga-Verknüpfung unter `as: :competition`. Wird gepiped, weil
  `order_by` sich über mehrere Aufrufe hinweg sammelt — was danach kommt,
  sortiert innerhalb der Liga.
  """
  def nach_liga(query) do
    order_by(query, [competition: c],
      asc: c.sport_id,
      asc: c.country,
      asc: c.tier,
      asc: c.name
    )
  end

  ## Übersicht

  @doc """
  Alle Ligen einer Saison mit ihren Teams und deren Trikots, fertig sortiert für
  die Übersicht: Ligen nach `tier`, Teams alphabetisch, Trikots in der Reihenfolge
  Heim → Auswärts → Ausweich → Sonder.

  Gibt eine Liste `{competition, [{team, [kit]}]}` zurück. Ligen ohne Teams in
  dieser Saison fallen raus.
  """
  def overview(season \\ current_season(), sport \\ nil) do
    team_seasons =
      from(ts in TeamSeason,
        where: ts.season == ^season,
        join: t in assoc(ts, :team),
        as: :team,
        join: c in assoc(ts, :competition),
        as: :competition,
        preload: [team: t, competition: c]
      )
      |> nur_sportart(sport)
      |> nach_liga()
      |> order_by([team: t], asc: t.name)
      |> Repo.all()

    kits_by_team = kits_by_team(Enum.map(team_seasons, & &1.team_id), season)

    team_seasons
    |> Enum.chunk_by(& &1.competition_id)
    |> Enum.map(fn [%{competition: competition} | _] = group ->
      teams = Enum.map(group, fn ts -> {ts.team, Map.get(kits_by_team, ts.team_id, [])} end)
      {competition, teams}
    end)
  end

  # Ohne Sportart bleibt es bei allem – so bedient dieselbe Abfrage die
  # Sportart-Seite und alles, was sportartuebergreifend fragt.
  defp nur_sportart(query, nil), do: query

  defp nur_sportart(query, %Sport{id: id}),
    do: from([competition: c] in query, where: c.sport_id == ^id)

  @doc """
  Bestimmte Trikots einer Saison, samt Verein und Liga, als Map über die ID.

  Für den Direktvergleich: der ist **sportartübergreifend**, das Raster
  darunter nicht. Ein Bundesliga-Trikot gegen ein NFL-Trikot zu stellen ist
  eine der wenigen Sachen, die diese App kann — dafür dürfen die verglichenen
  Trikots nicht aus der sportartgefilterten Übersicht kommen, sondern werden
  direkt über ihre IDs geholt.

  IDs, die es in dieser Saison nicht gibt, fehlen im Ergebnis. Ein geteilter
  Link aus der Vorsaison endet damit nicht mit leeren Karten, sondern mit
  weniger.
  """
  def kits_by_ids([], _season), do: %{}

  def kits_by_ids(ids, season) do
    from(k in Kit,
      join: t in assoc(k, :team),
      join: ts in TeamSeason,
      on: ts.team_id == k.team_id and ts.season == k.season,
      join: c in assoc(ts, :competition),
      where: k.id in ^ids and k.season == ^season,
      preload: [team: t],
      select: %{kit: k, team: t, competition: c}
    )
    |> Repo.all()
    |> Map.new(&{&1.kit.id, &1})
  end

  @doc """
  Alle Trikots einer Saison, flach und in Übersichts-Reihenfolge – die Grundmenge,
  aus der eine Rangliste gebaut wird. Teams sind vorgeladen.
  """
  def list_rankable_kits(season \\ current_season()) do
    from(k in Kit,
      join: t in assoc(k, :team),
      as: :team,
      join: ts in TeamSeason,
      on: ts.team_id == k.team_id and ts.season == k.season,
      join: c in assoc(ts, :competition),
      as: :competition,
      where: k.season == ^season,
      preload: [team: t]
    )
    |> nach_liga()
    |> order_by([k, team: t], asc: t.name, asc: kit_type_order(k))
    |> Repo.all()
  end

  @doc """
  Trikots für einen frei gewählten Ausschnitt – Saisons, Ligen, Vereine.

  Jede leere Liste heißt "keine Einschränkung", wie beim Reveal-Raum. Damit ist
  `%{}` schlicht "alles, was es gibt".

  Das ist die Grundlage dafür, eine Rangliste über etwas anderes als die
  laufende Saison zu bauen: alle Heimtrikots der Bundesliga 2026/27 genauso wie
  sämtliche Trikots eines Vereins über zehn Jahre.

  Gibt `[%{kit:, competition:}]` zurück – die Liga steht dabei, weil sie
  saisonabhängig ist und sich nicht am Trikot ablesen lässt. Sortiert nach
  Saison (neueste zuerst), dann Liga, Verein und Kit-Typ.

  Nimmt einen `Kitrank.Kits.Scope` oder alles, woraus sich einer bauen lässt.
  """
  def list_kits_for_scope(scope \\ %Scope{}) do
    scope = Scope.new(scope)

    from(k in Kit,
      join: t in assoc(k, :team),
      as: :team,
      join: ts in TeamSeason,
      on: ts.team_id == k.team_id and ts.season == k.season,
      join: c in assoc(ts, :competition),
      as: :competition,
      preload: [team: t],
      select: %{kit: k, competition: c}
    )
    |> order_by([k], desc: k.season)
    |> nach_liga()
    |> order_by([k, team: t], asc: t.name, asc: kit_type_order(k))
    |> for_scope(scope)
    |> Repo.all()
  end

  @doc """
  Schränkt eine Trikot-Abfrage auf einen Ausschnitt ein.

  Erwartet die Bindungen von `list_kits_for_scope/1`: Trikot zuerst, dann
  Verein, dann Saison-Zuordnung.
  """
  def for_scope(query, %Scope{} = scope) do
    query
    |> scope_by(:season, scope.seasons)
    |> scope_by(:competition_id, scope.competition_ids)
    |> scope_by(:team_id, scope.team_ids)
    |> scope_by(:kit_type, scope.kit_types)
  end

  # Eine leere Liste schraenkt nicht ein.
  defp scope_by(query, _field, []), do: query
  defp scope_by(query, :season, values), do: from([k] in query, where: k.season in ^values)

  defp scope_by(query, :competition_id, values),
    do: from([k, _t, ts] in query, where: ts.competition_id in ^values)

  defp scope_by(query, :team_id, values), do: from([k] in query, where: k.team_id in ^values)
  defp scope_by(query, :kit_type, values), do: from([k] in query, where: k.kit_type in ^values)

  @doc """
  Trikots für die Admin-Liste, mit Liga und optional darauf gefiltert.

  Bewusst ein `left_join`: ein Trikot, dessen Verein für diese Saison keiner
  Liga zugeordnet ist, taucht trotzdem auf – mit `competition: nil`. Sonst
  würden genau die Datensätze unsichtbar, die man im Admin finden muss, weil
  etwas fehlt.
  """
  def list_kits_for_admin(season, opts \\ []) do
    from(k in Kit,
      join: t in assoc(k, :team),
      left_join: ts in TeamSeason,
      on: ts.team_id == k.team_id and ts.season == k.season,
      left_join: c in assoc(ts, :competition),
      where: k.season == ^season,
      order_by: [asc: t.name, asc: kit_type_order(k)],
      preload: [team: t],
      select: %{kit: k, competition: c}
    )
    |> admin_league_filter(Keyword.get(opts, :competition_ids, []))
    |> admin_type_filter(Keyword.get(opts, :kit_types, []))
    |> admin_missing_filter(Keyword.get(opts, :missing, []))
    |> admin_search(Keyword.get(opts, :query))
    |> Repo.all()
  end

  defp admin_league_filter(query, []), do: query

  defp admin_league_filter(query, ids),
    do: from([k, _t, ts] in query, where: ts.competition_id in ^ids)

  defp admin_type_filter(query, []), do: query
  defp admin_type_filter(query, types), do: from([k] in query, where: k.kit_type in ^types)

  @doc """
  Was an einem Trikot fehlen kann – die Haken des Admin-Filters.

  Als Liste und nicht als Aufzählung im Template, damit Filter und Prüfung
  nicht auseinanderlaufen.
  """
  def admin_missing_kinds, do: ~w(bild shop liga)

  # Mehrere Haken heissen "eins davon fehlt", nicht "alles davon": man sucht
  # die Datensaetze, an denen noch etwas zu tun ist, nicht die schlimmsten.
  defp admin_missing_filter(query, []), do: query

  defp admin_missing_filter(query, kinds) do
    [erste | weitere] = Enum.map(kinds, &fehlt_bedingung/1)
    bedingung = Enum.reduce(weitere, erste, fn dyn, acc -> dynamic(^acc or ^dyn) end)

    from(q in query, where: ^bedingung)
  end

  defp fehlt_bedingung("bild"), do: dynamic([k], is_nil(k.cutout_url))
  defp fehlt_bedingung("shop"), do: dynamic([k], is_nil(k.source_shop_url))
  # Ohne Zuordnung taucht das Trikot in der Uebersicht gar nicht auf.
  defp fehlt_bedingung("liga"), do: dynamic([_k, _t, ts], is_nil(ts.id))

  defp admin_search(query, text) when text in [nil, ""], do: query

  defp admin_search(query, text) do
    # % und _ im Suchtext maskieren, sonst wird aus einer Eingabe versehentlich
    # ein Muster.
    muster = "%" <> String.replace(text, ~r/([%_\\])/, "\\\\\\1") <> "%"

    from([k, t] in query, where: ilike(t.name, ^muster) or ilike(t.short_code, ^muster))
  end

  @doc """
  Die Vereine, die in mindestens einer Saison einer Liga zugeordnet sind –
  also alles, worüber sich eine Rangliste bauen lässt.
  """
  def list_rankable_teams do
    from(t in Team,
      join: ts in TeamSeason,
      on: ts.team_id == t.id,
      distinct: true,
      order_by: t.name
    )
    |> Repo.all()
  end

  defp kits_by_team([], _season), do: %{}

  defp kits_by_team(team_ids, season) do
    from(k in Kit,
      where: k.team_id in ^team_ids and k.season == ^season,
      order_by: [asc: kit_type_order(k)]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.team_id)
  end

  @doc """
  Trikots, deren Kategorie ihre Sportart gar nicht kennt.

  Entsteht, wenn eine Sportart eine Kategorie ablegt: die NFL hatte 32
  Ausweichtrikots, weil der Import sie anfangs für alle Sportarten gleich
  anlegte.

  Gibt `%{loeschbar: [...], belegt: [...]}` zurück. **Löschbar** heißt: kein
  Bild, kein Shop-Link, kein Name, und in keiner Rangliste. Alles andere ist
  **belegt** und wird nur gemeldet — der Fremdschlüssel auf `ranking_entries`
  steht auf `delete_all`, ein Trikot mit Einträgen zu löschen würde es still
  aus fremden Ranglisten entfernen.
  """
  def orphan_kits(season \\ current_season()) do
    from(k in Kit,
      join: t in assoc(k, :team),
      join: ts in TeamSeason,
      on: ts.team_id == k.team_id and ts.season == k.season,
      join: c in assoc(ts, :competition),
      join: s in assoc(c, :sport),
      left_join: e in Kitrank.Rankings.RankingEntry,
      on: e.kit_id == k.id,
      where: k.season == ^season,
      where: fragment("NOT (? = ANY(?))", k.kit_type, s.kit_types),
      group_by: [k.id, t.id, s.id],
      select: %{
        kit: k,
        team: t,
        sport: s,
        eintraege: count(e.id)
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn eintrag ->
      if verwaist?(eintrag), do: :loeschbar, else: :belegt
    end)
    |> then(&%{loeschbar: Map.get(&1, :loeschbar, []), belegt: Map.get(&1, :belegt, [])})
  end

  defp verwaist?(%{kit: kit, eintraege: 0}) do
    is_nil(kit.cutout_url) and kit.model_image_urls in [nil, []] and
      is_nil(kit.source_shop_url) and is_nil(kit.name)
  end

  defp verwaist?(_), do: false

  @doc """
  Löscht, was `orphan_kits/1` als löschbar meldet, und gibt den Bericht zurück.
  """
  def remove_orphan_kits(season \\ current_season()) do
    bericht = orphan_kits(season)
    ids = Enum.map(bericht.loeschbar, & &1.kit.id)

    {geloescht, _} = Repo.delete_all(from k in Kit, where: k.id in ^ids)

    Map.put(bericht, :geloescht, geloescht)
  end

  @doc """
  Der Aufräum-Bericht als lesbarer Text — für die Konsole und den Server.

  `loeschen: true` löscht dabei wirklich; ohne sagt es nur, was passieren
  würde.
  """
  def aufraeum_bericht(opts \\ []) do
    season = Keyword.get(opts, :season, current_season())

    bericht =
      if Keyword.get(opts, :loeschen, false),
        do: remove_orphan_kits(season),
        else: Map.put(orphan_kits(season), :geloescht, 0)

    zeilen =
      for eintrag <- bericht.loeschbar ++ bericht.belegt do
        marke = if eintrag in bericht.belegt, do: "BELEGT ", else: "       "

        "  #{marke}#{eintrag.sport.slug} · #{eintrag.team.short_code} · " <>
          "#{eintrag.kit.kit_type}" <>
          if(eintrag.eintraege > 0, do: " (#{eintrag.eintraege} Ranglisten-Einträge)", else: "")
      end

    """

    Saison #{season}
      Ohne Kategorie in ihrer Sportart: #{length(bericht.loeschbar) + length(bericht.belegt)}
      Davon löschbar:                   #{length(bericht.loeschbar)}
      Davon belegt (bleibt stehen):     #{length(bericht.belegt)}
      Gelöscht:                         #{bericht.geloescht}
    #{Enum.join(zeilen, "\n")}
    """
  end

  @doc """
  Die Sportart eines Vereins in einer Saison — über seine Liga.

  `nil`, wenn der Verein in dieser Saison keiner Liga zugeordnet ist. Am
  Verein selbst hängt die Sportart bewusst nicht: sie ergibt sich aus der
  Liga, und die kann von Saison zu Saison eine andere sein.
  """
  def sport_for_team(nil, _season), do: nil
  def sport_for_team(_team_id, nil), do: nil

  def sport_for_team(team_id, season) do
    from(ts in TeamSeason,
      join: c in assoc(ts, :competition),
      join: s in assoc(c, :sport),
      where: ts.team_id == ^team_id and ts.season == ^season,
      select: s,
      limit: 1
    )
    |> Repo.one()
  end

  ## Sports

  def list_sports, do: Repo.all(from s in Sport, order_by: s.name)

  @doc """
  Die Sportarten, die in einer Saison überhaupt Vereine haben — mit Liga- und
  Vereinszahl, in derselben Reihenfolge wie überall sonst.

  Grundlage der Startseite. Eine Sportart ohne Vereine wäre dort eine Kachel,
  die auf eine leere Seite führt.
  """
  def list_sports_for_season(season \\ current_season()) do
    from(s in Sport,
      join: c in assoc(s, :competitions),
      join: ts in TeamSeason,
      on: ts.competition_id == c.id and ts.season == ^season,
      join: t in assoc(ts, :team),
      group_by: s.id,
      order_by: s.id,
      select: %{
        sport: s,
        competition_count: count(c.id, :distinct),
        team_count: count(ts.team_id, :distinct),
        # Ein paar Vereinsfarben fuer die Kachel. In derselben Abfrage, weil
        # eine zweite Runde fuer einen Zierstreifen nicht lohnt – und die
        # Uebersicht dafuer zu laden erst recht nicht: die zieht alle Trikots.
        colors: fragment("array_agg(DISTINCT ?)", t.primary_color)
      }
    )
    |> Repo.all()
    |> Enum.map(fn eintrag ->
      %{eintrag | colors: eintrag.colors |> Enum.reject(&is_nil/1) |> Enum.take(12)}
    end)
  end

  def get_sport!(id), do: Repo.get!(Sport, id)
  def get_sport_by_slug(slug), do: Repo.get_by(Sport, slug: slug)

  def create_sport(attrs) do
    %Sport{} |> Sport.changeset(attrs) |> Repo.insert()
  end

  def update_sport(%Sport{} = sport, attrs) do
    sport |> Sport.changeset(attrs) |> Repo.update()
  end

  def delete_sport(%Sport{} = sport), do: Repo.delete(sport)
  def change_sport(%Sport{} = sport, attrs \\ %{}), do: Sport.changeset(sport, attrs)

  ## Competitions

  def list_competitions do
    from(c in Competition, as: :competition, preload: :sport)
    |> nach_liga()
    |> Repo.all()
  end

  @doc """
  Die Ligen, in denen eine Saison überhaupt Vereine hat.

  Gibt es dafür `overview/1`? Ja — aber das lädt jede Liga mit allen Vereinen
  und allen Trikots. Wer nur wissen will, welche Ligen zur Auswahl stehen,
  bezahlt dafür den ganzen Datenbestand: auf `/reveal/new` waren das zwei
  Sekunden pro Seitenaufruf, und weil `mount` bei LiveView zweimal läuft
  (statisch und verbunden), doppelt.
  """
  def list_competitions_for_season(season) do
    from(c in Competition,
      as: :competition,
      join: ts in TeamSeason,
      on: ts.competition_id == c.id and ts.season == ^season,
      distinct: true,
      preload: :sport
    )
    |> nach_liga()
    |> Repo.all()
  end

  @doc """
  Welche Trikot-Typen es in einer Saison gibt — als Liste der Bezeichner.

  Dieselbe Sache: `list_kits/1` lädt alle Trikots samt Vereinen, um am Ende
  vier Zeichenketten zu unterscheiden.
  """
  def list_kit_types(season \\ current_season()) do
    vorhanden =
      from(k in Kit, where: k.season == ^season, distinct: true, select: k.kit_type)
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(Kit.kit_types(), &MapSet.member?(vorhanden, &1))
  end

  def get_competition!(id), do: Repo.get!(Competition, id) |> Repo.preload(:sport)

  def create_competition(attrs) do
    %Competition{} |> Competition.changeset(attrs) |> Repo.insert()
  end

  def update_competition(%Competition{} = competition, attrs) do
    competition |> Competition.changeset(attrs) |> Repo.update()
  end

  def delete_competition(%Competition{} = competition), do: Repo.delete(competition)

  def change_competition(%Competition{} = competition, attrs \\ %{}),
    do: Competition.changeset(competition, attrs)

  ## Teams

  def list_teams, do: Repo.all(from t in Team, order_by: t.name)

  @doc """
  Vereine einer Saison, nach Liga gruppiert — die Form, in der die Admin-Liste
  sie zeigt.

  Gibt `[{competition_or_nil, [team]}]` in Liga-Reihenfolge zurück, Vereine
  darin alphabetisch.

  Der `left_join` ist die Absicht: ein Verein ohne Zuordnung in dieser Saison
  steht unter `nil` am Ende und verschwindet nicht. Er existiert weiter, muss
  sich bearbeiten lassen — und ist obendrein genau der Datensatz, bei dem
  jemand nachsehen sollte. In Postgres sortieren NULLs aufsteigend ans Ende,
  die Gruppe steht damit von selbst hinten.
  """
  def list_teams_by_competition(season \\ current_season()) do
    from(t in Team,
      left_join: ts in TeamSeason,
      on: ts.team_id == t.id and ts.season == ^season,
      left_join: c in assoc(ts, :competition),
      as: :competition,
      select: %{team: t, competition: c}
    )
    |> nach_liga()
    |> order_by([t], asc: t.name)
    |> Repo.all()
    |> Enum.chunk_by(fn %{competition: competition} -> competition && competition.id end)
    |> Enum.map(fn [%{competition: competition} | _] = gruppe ->
      {competition, Enum.map(gruppe, & &1.team)}
    end)
  end

  def get_team!(id), do: Repo.get!(Team, id)

  @doc "Team samt seiner Trikots für eine Saison – für das Detail-Modal der Übersicht."
  def get_team_with_kits!(id, season \\ current_season()) do
    kits_query = from(k in Kit, where: k.season == ^season, order_by: [asc: kit_type_order(k)])

    Team
    |> Repo.get!(id)
    |> Repo.preload(kits: kits_query)
  end

  def create_team(attrs) do
    %Team{} |> Team.changeset(attrs) |> Repo.insert()
  end

  def update_team(%Team{} = team, attrs) do
    team |> Team.changeset(attrs) |> Repo.update()
  end

  def delete_team(%Team{} = team), do: Repo.delete(team)
  def change_team(%Team{} = team, attrs \\ %{}), do: Team.changeset(team, attrs)

  ## TeamSeasons

  def list_team_seasons(season \\ current_season()) do
    from(ts in TeamSeason,
      where: ts.season == ^season,
      join: t in assoc(ts, :team),
      order_by: t.name,
      preload: [team: t, competition: :sport]
    )
    |> Repo.all()
  end

  @doc "Alle Saisons, für die überhaupt Daten existieren – neueste zuerst."
  def list_seasons do
    from(ts in TeamSeason, select: ts.season, distinct: true, order_by: [desc: ts.season])
    |> Repo.all()
  end

  def get_team_season!(id), do: Repo.get!(TeamSeason, id)

  def create_team_season(attrs) do
    %TeamSeason{} |> TeamSeason.changeset(attrs) |> Repo.insert()
  end

  def update_team_season(%TeamSeason{} = team_season, attrs) do
    team_season |> TeamSeason.changeset(attrs) |> Repo.update()
  end

  def delete_team_season(%TeamSeason{} = team_season), do: Repo.delete(team_season)

  def change_team_season(%TeamSeason{} = team_season, attrs \\ %{}),
    do: TeamSeason.changeset(team_season, attrs)

  ## Kits

  def list_kits(season \\ current_season()) do
    from(k in Kit,
      where: k.season == ^season,
      join: t in assoc(k, :team),
      order_by: [asc: t.name, asc: kit_type_order(k)],
      preload: [team: t]
    )
    |> Repo.all()
  end

  def get_kit!(id), do: Repo.get!(Kit, id) |> Repo.preload(:team)

  def create_kit(attrs) do
    %Kit{} |> Kit.changeset(attrs) |> Repo.insert()
  end

  def update_kit(%Kit{} = kit, attrs) do
    kit |> Kit.changeset(attrs) |> Repo.update()
  end

  def delete_kit(%Kit{} = kit), do: Repo.delete(kit)
  def change_kit(%Kit{} = kit, attrs \\ %{}), do: Kit.changeset(kit, attrs)
end
