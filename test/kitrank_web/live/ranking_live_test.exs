defmodule KitrankWeb.RankingLiveTest do
  @moduledoc """
  Der Weg, den eine Rangliste wirklich nimmt: anlegen, auswählen, sortieren,
  teilen — und was passiert, wenn jemand am falschen Link zieht.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Rankings

  defp league(opts) do
    league_fixture(Keyword.put_new(opts, :season, Kits.current_season()))
  end

  defp ranking_with(kits) do
    {:ok, ranking} = Rankings.create_ranking(%{display_name: "Testliste"})
    Enum.each(kits, &Rankings.add_kit(ranking, &1.id))
    ranking
  end

  describe "Anlegen" do
    test "legt eine Rangliste an und führt zur Auswahl", %{conn: conn} do
      league(team_count: 1)
      {:ok, view, _html} = live(conn, ~p"/rankings/new")

      {:error, {:live_redirect, %{to: to}}} =
        view |> form("#new-ranking", ranking: %{display_name: "Toms Liste"}) |> render_submit()

      assert to =~ ~r{^/rankings/[\w-]+/auswahl$}

      assert [%{display_name: "Toms Liste"}] = Kitrank.Repo.all(Rankings.Ranking)
    end

    test "geht auch ohne Namen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rankings/new")

      assert {:error, {:live_redirect, _}} =
               view |> form("#new-ranking", ranking: %{display_name: ""}) |> render_submit()
    end
  end

  describe "Auswählen" do
    setup do
      %{kits: kits, competition: competition} =
        league(team_count: 2, kit_types: ["home", "away"])

      %{kits: kits, competition: competition, ranking: ranking_with([])}
    end

    test "nimmt ein Trikot auf und wieder heraus", %{conn: conn, ranking: r, kits: [kit | _]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="toggle_kit"][phx-value-id="#{kit.id}"]})
      |> render_click()

      assert Rankings.count_entries(r.id) == 1

      view
      |> element(~s{button[phx-click="toggle_kit"][phx-value-id="#{kit.id}"]})
      |> render_click()

      assert Rankings.count_entries(r.id) == 0
    end

    test "nimmt eine ganze Gruppe auf und wieder heraus", %{
      conn: conn,
      ranking: r,
      competition: competition,
      kits: kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")
      sel = ~s{button[phx-click="toggle_group"][phx-value-name="#{competition.name}"]}

      html = view |> element(sel) |> render_click()
      assert Rankings.count_entries(r.id) == length(kits)
      assert html =~ "Alle abwählen"

      view |> element(sel) |> render_click()
      assert Rankings.count_entries(r.id) == 0
    end

    test "behält die Notiz, wenn eine Gruppe nochmal komplett hinzugefügt wird", %{
      conn: conn,
      ranking: r,
      competition: competition,
      kits: [kit | _]
    } do
      {:ok, _} = Rankings.add_kit(r, kit.id)
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(r.id, 1), "wichtig")

      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="toggle_group"][phx-value-name="#{competition.name}"]})
      |> render_click()

      assert Rankings.get_entry_at(r.id, 1).note == "wichtig"
    end

    test "zählt mit, was gewählt ist", %{conn: conn, ranking: r, kits: [a, b | _]} do
      assert Rankings.add_kits(r, [a.id, b.id]) == 2
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ "2</span>"
      assert html =~ "Trikots in der Liste"
    end
  end

  describe "Gemerkte Ranglisten" do
    test "die Bearbeiten-Seite gibt dem Browser mit, was er sich merken soll", %{conn: conn} do
      %{kits: kits} = league(team_count: 1, kit_types: ["home"])
      r = ranking_with(kits)

      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      assert html =~ ~s(phx-hook="RememberRanking")
      assert html =~ ~s(data-token="#{r.edit_token}")
      assert html =~ ~s(data-slug="#{r.share_slug}")
    end

    test "schlägt gemerkte Tokens nach und zeigt sie an", %{conn: conn} do
      %{kits: kits} = league(team_count: 2, kit_types: ["home"])
      a = ranking_with(kits)
      {:ok, b} = Rankings.create_ranking(%{display_name: "Zweite Liste"})

      {:ok, view, _html} = live(conn, ~p"/rankings/new")

      html =
        render_hook(view, "remembered_rankings", %{"tokens" => [a.edit_token, b.edit_token]})

      assert html =~ "In diesem Browser gemerkt"
      assert html =~ "Testliste"
      assert html =~ "Zweite Liste"
      assert html =~ "2 Trikots"
      assert html =~ ~s(href="/rankings/#{a.edit_token}/edit")
    end

    test "wirft verschwundene Ranglisten aus dem Browser", %{conn: conn} do
      {:ok, weg} = Rankings.create_ranking(%{})
      {:ok, da} = Rankings.create_ranking(%{display_name: "Bleibt"})
      {:ok, _} = Rankings.delete_ranking(weg)

      {:ok, view, _html} = live(conn, ~p"/rankings/new")
      render_hook(view, "remembered_rankings", %{"tokens" => [weg.edit_token, da.edit_token]})

      assert_push_event(view, "prune_rankings", %{keep: keep})
      assert keep == [da.edit_token]
      assert render(view) =~ "Bleibt"
    end

    test "'Vergessen' nimmt sie aus der Liste und aus dem Browser", %{conn: conn} do
      {:ok, r} = Rankings.create_ranking(%{display_name: "Weg damit"})

      {:ok, view, _html} = live(conn, ~p"/rankings/new")
      render_hook(view, "remembered_rankings", %{"tokens" => [r.edit_token]})

      html = view |> element(~s{button[phx-value-token="#{r.edit_token}"]}) |> render_click()

      assert_push_event(view, "forget_ranking", %{token: token})
      assert token == r.edit_token
      refute html =~ "Weg damit"
      # Vergessen heisst nur vergessen – die Rangliste selbst bleibt.
      assert Rankings.get_ranking_by_edit_token(r.edit_token)
    end

    test "ignoriert erfundene Tokens", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rankings/new")

      html = render_hook(view, "remembered_rankings", %{"tokens" => ["quatsch", "auch-quatsch"]})

      refute html =~ "In diesem Browser gemerkt"
    end
  end

  describe "Ausschnitt wählen" do
    setup do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)

      %{kits: erste_kits} =
        league(competition: erste, team_count: 2, kit_types: ["home", "away"])

      %{kits: zweite_kits} =
        league(competition: zweite, team_count: 2, kit_types: ["home", "away"])

      %{
        erste: erste,
        zweite: zweite,
        erste_kits: erste_kits,
        zweite_kits: zweite_kits,
        ranking: ranking_with([])
      }
    end

    test "zeigt alle drei Achsen", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ "Worüber rankst du?"
      assert html =~ ~s{phx-value-axis="seasons"}
      assert html =~ ~s{phx-value-axis="competitions"}
      assert html =~ ~s{phx-value-axis="teams"}
    end

    test "startet bei der laufenden Saison, ohne weitere Einschränkung", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      # 4 Vereine × 2 Trikots
      assert html =~ "8 Trikots · #{Kits.current_season()}"
    end

    test "grenzt auf eine Liga ein", %{conn: conn, ranking: r, erste: erste, zweite_kits: [z | _]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-value-axis="competitions"][phx-value-item="#{erste.id}"]})
        |> render_click()

      assert html =~ "4 Trikots"
      refute html =~ ~s{phx-click="toggle_kit" phx-value-id="#{z.id}"}
    end

    test "verträgt den Payload, den der Browser wirklich schickt", %{
      conn: conn,
      ranking: r,
      erste: erste
    } do
      # LiveView setzt beim Klick meta.value auf el.value – bei einem <button>
      # ein leerer String. Hiess der eigene Parameter "value", wurde er damit
      # stillschweigend ueberschrieben und String.to_integer("") flog. Ueber
      # element() |> render_click() faellt das nicht auf, weil dort nur die
      # phx-value-Attribute mitgehen.
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        render_click(view, "toggle_filter", %{
          "axis" => "competitions",
          "item" => to_string(erste.id),
          "value" => ""
        })

      assert html =~ "4 Trikots"
    end

    test "grenzt auf einen Verein ein", %{conn: conn, ranking: r, erste_kits: kits} do
      team_id = hd(kits).team_id
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-value-axis="teams"][phx-value-item="#{team_id}"]})
        |> render_click()

      assert html =~ "2 Trikots"
    end

    test "'Alle' hebt die Einschränkung wieder auf", %{conn: conn, ranking: r, erste: erste} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-value-axis="competitions"][phx-value-item="#{erste.id}"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-click="clear_filter"][phx-value-axis="competitions"]})
        |> render_click()

      assert html =~ "8 Trikots"
    end

    test "sagt es, wenn die Kombination nichts übrig lässt", %{
      conn: conn,
      ranking: r,
      erste: erste,
      zweite_kits: kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      # Erste Liga, aber ein Verein aus der zweiten.
      view
      |> element(~s{button[phx-value-axis="competitions"][phx-value-item="#{erste.id}"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-value-axis="teams"][phx-value-item="#{hd(kits).team_id}"]})
        |> render_click()

      assert html =~ "Nichts im Ausschnitt"
    end

    test "kommt man wieder, ist der Ausschnitt der bisherigen Auswahl aktiv", %{
      conn: conn,
      ranking: r,
      erste_kits: [kit | _]
    } do
      {:ok, _} = Rankings.add_kit(r, kit.id)

      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ "· #{kit.season}"
    end
  end

  describe "Über mehrere Saisons" do
    setup do
      competition = competition_fixture(name: "Bundesliga", tier: 1)

      # Derselbe Verein in drei Saisons – der Fall "Trikots eines Vereins über
      # die Jahre ranken".
      team = team_fixture(name: "Hamburger SV", short_code: "HSV")

      kits =
        for season <- ["2026/27", "2025/26", "2024/25"] do
          {:ok, _} =
            Kits.create_team_season(%{
              team_id: team.id,
              competition_id: competition.id,
              season: season
            })

          kit_fixture(team_id: team.id, season: season, kit_type: "home")
        end

      # Ein zweiter Verein, nur in der laufenden Saison.
      %{teams: [anderer]} = league(competition: competition, team_count: 1, kit_types: ["home"])

      %{team: team, anderer: anderer, kits: kits, ranking: ranking_with([])}
    end

    test "'Alle' bei der Saison öffnet das Archiv", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-click="clear_filter"][phx-value-axis="seasons"]})
        |> render_click()

      assert html =~ "4 Trikots · alle Saisons"
      # Über mehrere Saisons wird nach Saison gruppiert, nicht nach Liga.
      assert html =~ "2024/25"
      assert html =~ "2025/26"
    end

    test "ein Verein über zehn Jahre", %{conn: conn, ranking: r, team: team} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="clear_filter"][phx-value-axis="seasons"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-value-axis="teams"][phx-value-item="#{team.id}"]})
        |> render_click()

      assert html =~ "3 Trikots · alle Saisons, HSV"
      assert html =~ "2024/25"
    end

    test "nimmt alle drei Saisons in die Rangliste", %{conn: conn, ranking: r, team: team} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="clear_filter"][phx-value-axis="seasons"]})
      |> render_click()

      view
      |> element(~s{button[phx-value-axis="teams"][phx-value-item="#{team.id}"]})
      |> render_click()

      view
      |> element(~s{button[phx-click="quick_select"][phx-value-type="all"]})
      |> render_click()

      saisons = Rankings.list_entries(r) |> Enum.map(& &1.kit.season) |> Enum.sort()
      assert saisons == ["2024/25", "2025/26", "2026/27"]
    end

    test "der Ausschnitt kehrt beim Wiederkommen zurück", %{conn: conn, ranking: r, kits: kits} do
      Enum.each(kits, &Rankings.add_kit(r, &1.id))

      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      # Drei Saisons in der Liste -> drei Saisons im Ausschnitt.
      assert html =~ "3 Saisons"
    end
  end

  describe "Schnellauswahl" do
    setup do
      erste = competition_fixture(name: "Erste Liga", tier: 1)
      zweite = competition_fixture(name: "Zweite Liga", tier: 2)
      %{kits: erste_kits} = league(competition: erste, team_count: 2, kit_types: ["home", "away"])

      %{kits: zweite_kits} =
        league(competition: zweite, team_count: 2, kit_types: ["home", "away"])

      %{
        erste: erste,
        erste_kits: erste_kits,
        zweite_kits: zweite_kits,
        ranking: ranking_with([])
      }
    end

    test "'Alle Heim' nimmt nur Heimtrikots", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="quick_select"][phx-value-type="home"]})
      |> render_click()

      typen = Rankings.list_entries(r) |> Enum.map(& &1.kit.kit_type) |> Enum.uniq()
      assert typen == ["home"]
      assert Rankings.count_entries(r.id) == 4
    end

    test "wirkt nur auf den gewählten Ausschnitt", %{
      conn: conn,
      ranking: r,
      erste: erste,
      zweite_kits: zweite_kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-value-axis="competitions"][phx-value-item="#{erste.id}"]})
      |> render_click()

      view
      |> element(~s{button[phx-click="quick_select"][phx-value-type="home"]})
      |> render_click()

      gewaehlt = Rankings.list_entries(r) |> Enum.map(& &1.kit_id) |> MapSet.new()
      assert Rankings.count_entries(r.id) == 2

      for kit <- zweite_kits do
        refute MapSet.member?(gewaehlt, kit.id), "Trikot ausserhalb des Ausschnitts ist drin"
      end
    end

    test "nochmal drücken nimmt sie wieder heraus", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")
      sel = ~s{button[phx-click="quick_select"][phx-value-type="home"]}

      html = view |> element(sel) |> render_click()
      assert html =~ "Heim abwählen"

      view |> element(sel) |> render_click()
      assert Rankings.count_entries(r.id) == 0
    end

    test "bietet keinen Knopf für Kit-Typen an, die es nicht gibt", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ ~s{phx-value-type="home"}
      assert html =~ ~s{phx-value-type="away"}
      refute html =~ ~s{phx-value-type="third"}
    end

    test "eine Gruppe auf einmal", %{conn: conn, ranking: r, erste_kits: erste_kits} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-click="toggle_group"][phx-value-name="Erste Liga"]})
        |> render_click()

      assert Rankings.count_entries(r.id) == length(erste_kits)
      assert html =~ "Alle abwählen"
    end
  end

  describe "Detailansicht beim Sortieren" do
    setup do
      %{kits: [kit | _] = kits} = league(team_count: 3, kit_types: ["home"])

      {:ok, kit} =
        Kits.update_kit(kit, %{
          cutout_url: "https://example.com/cutout.jpg",
          model_image_urls: ["https://example.com/model.jpg"]
        })

      %{kits: kits, kit: kit, ranking: ranking_with(kits)}
    end

    test "öffnet sich aus der Zeile", %{conn: conn, ranking: r, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      html =
        view
        |> element(~s{button[data-role="detail-figure"][phx-value-id="#{kit.id}"]})
        |> render_click()

      assert html =~ ~s(id="entry-detail")
      assert html =~ "Platz 1 von 3"
      assert html =~ "https://example.com/cutout.jpg"
    end

    test "blättert durch die Bilder", %{conn: conn, ranking: r, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> element(~s{button[data-role="detail-figure"][phx-value-id="#{kit.id}"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-click="detail_image"][phx-value-index="1"]})
        |> render_click()

      assert html =~ "https://example.com/model.jpg"
    end

    test "speichert die Notiz und trägt sie in die Zeile zurück", %{
      conn: conn,
      ranking: r,
      kit: kit
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> element(~s{button[data-role="detail-figure"][phx-value-id="#{kit.id}"]})
      |> render_click()

      entry = Rankings.get_entry_at(r.id, 1)

      html =
        view
        |> element("#detail-note")
        |> render_change(%{"entry_id" => to_string(entry.id), "note" => "viel zu bunt"})

      assert Rankings.get_entry_at(r.id, 1).note == "viel zu bunt"
      # Das Feld in der Zeile steht unter phx-update="ignore" – es muss trotzdem
      # den neuen Text bekommen.
      assert html =~ "viel zu bunt"
    end

    test "verschiebt aus der Detailansicht heraus", %{conn: conn, ranking: r, kits: [_, _, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> element(~s{button[data-role="detail-figure"][phx-value-id="#{c.id}"]})
      |> render_click()

      view
      |> element(~s{#entry-detail button[phx-click="move"][phx-value-delta="-1"]})
      |> render_click()

      assert Rankings.get_entry_at(r.id, 2).kit_id == c.id
    end

    test "lässt sich schließen", %{conn: conn, ranking: r, kit: kit} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> element(~s{button[data-role="detail-figure"][phx-value-id="#{kit.id}"]})
      |> render_click()

      html = view |> element(~s{#entry-detail button[aria-label="Schließen"]}) |> render_click()

      refute html =~ ~s(id="entry-detail")
    end
  end

  describe "Sortieren" do
    setup do
      %{kits: kits} = league(team_count: 3, kit_types: ["home"])
      %{kits: kits, ranking: ranking_with(kits)}
    end

    test "übernimmt die Reihenfolge aus dem Drag-Hook", %{conn: conn, ranking: r, kits: kits} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      neu = kits |> Enum.map(&to_string(&1.id)) |> Enum.reverse()
      render_hook(view, "reorder", %{"kit_ids" => neu})

      assert Rankings.list_entries(r) |> Enum.map(&to_string(&1.kit_id)) == neu
    end

    test "verwirft eine Reihenfolge, die nicht mehr zum Stand passt", %{
      conn: conn,
      ranking: r,
      kits: [a | _] = kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      # Ein zweiter Tab hat inzwischen etwas entfernt.
      {:ok, _} = Rankings.remove_kit(r, a.id)

      html = render_hook(view, "reorder", %{"kit_ids" => Enum.map(kits, &to_string(&1.id))})

      assert html =~ "zwischendurch geändert"
      assert Rankings.count_entries(r.id) == 2
    end

    test "setzt einen Eintrag über die Platzziffer", %{conn: conn, ranking: r, kits: [a, b, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> form("#platz-form-#{c.id}", %{"position" => "1"})
      |> render_submit()

      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) == [c.id, a.id, b.id]
    end

    test "Wegklicken speichert genauso wie Enter", %{conn: conn, ranking: r, kits: [a, b, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      # phx-blur schickt den Feldinhalt unter "value" – nicht unter "position".
      render_blur(view, "move_to", %{"kit-id" => to_string(a.id), "value" => "3"})

      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) == [b.id, c.id, a.id]
    end

    test "eine Zahl jenseits der Liste rutscht ans Ende", %{
      conn: conn,
      ranking: r,
      kits: [a, b, c]
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view |> form("#platz-form-#{a.id}", %{"position" => "99"}) |> render_submit()

      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) == [b.id, c.id, a.id]
    end

    test "eine leere Eingabe laesst die Liste in Ruhe", %{conn: conn, ranking: r, kits: [a, b, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      html = view |> form("#platz-form-#{c.id}", %{"position" => ""}) |> render_submit()

      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) == [a.id, b.id, c.id]
      # Der halb getippte Wert darf nicht stehen bleiben.
      assert html =~ ~s(name="position" value="3")
    end

    test "das Feld kennt die Laenge der Liste", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      assert html =~ ~s(max="3")
    end

    test "schiebt einen Eintrag nach oben", %{conn: conn, ranking: r, kits: [a, b, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view
      |> element(~s{button[phx-click="move"][phx-value-id="#{c.id}"][phx-value-delta="-1"]})
      |> render_click()

      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) == [a.id, c.id, b.id]
    end

    test "die Pfeile an den Rändern sind aus", %{conn: conn, ranking: r, kits: [a, _, c]} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      assert view
             |> element(~s{button[phx-value-id="#{a.id}"][phx-value-delta="-1"]})
             |> render() =~ "disabled"

      assert view
             |> element(~s{button[phx-value-id="#{c.id}"][phx-value-delta="1"]})
             |> render() =~ "disabled"
    end

    test "entfernt einen Eintrag und schließt die Lücke", %{
      conn: conn,
      ranking: r,
      kits: [a, b, c]
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view |> element(~s{button[phx-click="remove"][phx-value-id="#{b.id}"]}) |> render_click()

      assert Rankings.list_entries(r) |> Enum.map(&{&1.position, &1.kit_id}) ==
               [{1, a.id}, {2, c.id}]
    end

    test "speichert eine Notiz", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")
      entry = Rankings.get_entry_at(r.id, 1)

      view
      |> element(~s{#note-form-#{entry.id}})
      |> render_change(%{"entry_id" => to_string(entry.id), "note" => "sieht komisch aus"})

      assert Rankings.get_entry_at(r.id, 1).note == "sieht komisch aus"
    end

    test "ändert den Namen der Rangliste", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      view |> form("#ranking-name") |> render_change(ranking: %{display_name: "Neuer Name"})

      assert Rankings.get_ranking_by_edit_token(r.edit_token).display_name == "Neuer Name"
    end

    test "eine leere Liste schickt zurück zur Auswahl", %{conn: conn} do
      leer = ranking_with([])
      {:ok, _view, html} = live(conn, ~p"/rankings/#{leer.edit_token}/edit")

      assert html =~ "Noch nichts ausgewählt"
      assert html =~ ~s(href="/rankings/#{leer.edit_token}/auswahl")
    end
  end

  describe "Vergleichen" do
    setup do
      %{kits: kits} = league(team_count: 4, kit_types: ["home"])
      %{kits: kits, ranking: ranking_with(kits)}
    end

    defp waehle(view, seite) do
      view
      |> element(~s{button[phx-click="duel_pick"][phx-value-side="#{seite}"]})
      |> render_click()
    end

    test "stellt sie auf dem Handy nebeneinander, nicht untereinander", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      # Untereinander sah man immer nur ein Trikot und musste zum anderen
      # scrollen — bei „welches von beiden" die falsche Anordnung.
      assert html =~ "grid grid-cols-2"
      refute html =~ ~r/class="mt-6 grid gap-4 sm:grid-cols-2"/
    end

    test "aus jeder Karte fuehrt ein Weg ins Detail", %{conn: conn, ranking: r} do
      {:ok, view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      assert length(Regex.scan(~r/data-role="duel-detail"/, html)) == 2

      [_, kit_id] =
        Regex.run(~r/<button[^>]*phx-value-id="(\d+)"[^>]*data-role="duel-detail"/, html)

      html =
        view
        |> element(~s{[data-role="duel-detail"][phx-value-id="#{kit_id}"]})
        |> render_click()

      # Was das Duell nicht zeigt: die weiteren Bilder und der Shop-Link.
      assert html =~ ~s(id="entry-detail")
      assert html =~ "Zum Vereinsshop" or html =~ "Notiz"
    end

    test "der Detail-Knopf liegt nicht im Waehl-Knopf", %{conn: conn, ranking: r} do
      # Ein <button> in einem <button> ist ungueltiges HTML; der Browser
      # zerlegt die Verschachtelung und die Karte verliert ihre Klickflaeche.
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      [karte] =
        Regex.run(~r/<button[^>]*data-role="duel-pick".*?<\/button>/s, html) |> Enum.take(1)

      refute karte =~ "duel-detail"
    end

    test "waehrend das Detail offen ist, waehlen die Pfeiltasten nicht", %{conn: conn, ranking: r} do
      {:ok, view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      assert html =~ ~s(phx-window-keydown="duel_key")

      [_, kit_id] =
        Regex.run(~r/<button[^>]*phx-value-id="(\d+)"[^>]*data-role="duel-detail"/, html)

      html =
        view |> element(~s{[data-role="duel-detail"][phx-value-id="#{kit_id}"]}) |> render_click()

      refute html =~ ~s(phx-window-keydown="duel_key")
    end

    test "im Duell steht kein Platz — der wird ja gerade ermittelt", %{conn: conn, ranking: r} do
      {:ok, view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      [_, kit_id] =
        Regex.run(~r/<button[^>]*phx-value-id="(\d+)"[^>]*data-role="duel-detail"/, html)

      html =
        view |> element(~s{[data-role="duel-detail"][phx-value-id="#{kit_id}"]}) |> render_click()

      assert html =~ "Noch im Vergleich"
      refute html =~ "Höher"
      refute html =~ "Tiefer"
    end

    test "stellt zwei Trikots gegeneinander", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      assert html =~ "Welches gefällt dir besser?"
      assert html =~ "Trikot 2 von 4"
      # Genau zwei Karten, nicht die ganze Liste.
      assert length(Regex.scan(~r/phx-click="duel_pick"/, html)) == 2
    end

    test "speichert nach jeder Antwort", %{conn: conn, ranking: r, kits: kits} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")
      vorher = Rankings.list_entries(r) |> Enum.map(& &1.kit_id)

      waehle(view, "new")

      nachher = Rankings.list_entries(r) |> Enum.map(& &1.kit_id)
      # Reihenfolge veraendert, aber nichts verloren – abbrechen kostet nichts.
      assert Enum.sort(nachher) == Enum.sort(vorher)
      assert length(nachher) == length(kits)
    end

    test "kommt bis zum Ende und meldet den Entwurf", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      # Immer das neue waehlen – nach genuegend Klicks ist es durch.
      html =
        Enum.reduce_while(1..30, nil, fn _, _ ->
          if Enum.any?(
               [waehle(view, "new")],
               &String.contains?(&1, "Dein Entwurf steht")
             ),
             do: {:halt, render(view)},
             else: {:cont, nil}
        end)

      assert html =~ "Dein Entwurf steht"
      assert html =~ "Vergleichen"
      assert html =~ ~s(href="/rankings/#{r.edit_token}/edit")
    end

    test "immer das neue wählen dreht die Reihenfolge um", %{conn: conn, ranking: r, kits: kits} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      Enum.each(1..30, fn _ ->
        unless render(view) =~ "Dein Entwurf steht", do: waehle(view, "new")
      end)

      # Wer jedes neue Trikot vorzieht, landet bei der umgekehrten Ausgangsfolge.
      assert Rankings.list_entries(r) |> Enum.map(& &1.kit_id) ==
               kits |> Enum.map(& &1.id) |> Enum.reverse()
    end

    test "Pfeiltasten wählen auch", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      html = view |> element("#duell") |> render_keydown(%{"key" => "ArrowLeft"})
      assert html =~ "Vergleiche"

      html = view |> element("#duell") |> render_keydown(%{"key" => "ArrowRight"})
      assert html =~ "Vergleiche"
    end

    test "nochmal durchgehen fängt neu an", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")
      waehle(view, "new")
      waehle(view, "new")

      html = view |> element(~s{button[phx-click="duel_restart"]}) |> render_click()

      assert html =~ "0 Vergleiche"
      assert html =~ "Trikot 2 von 4"
    end

    test "mit weniger als zwei Trikots gibt es nichts zu vergleichen", %{conn: conn} do
      %{kits: [kit]} = league(team_count: 1, kit_types: ["home"])
      r = ranking_with([kit])

      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/duell")

      assert html =~ "Dafür braucht es zwei"
      refute html =~ ~s{phx-click="duel_pick"}
    end

    test "steht als eigener Schritt in der Navigation", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ ~s(href="/rankings/#{r.edit_token}/duell")
      assert html =~ "Vergleichen lassen"
      # Der Weg von Hand bleibt daneben stehen.
      assert html =~ "Selbst sortieren"
    end
  end

  describe "Teilen" do
    setup do
      %{kits: kits} = league(team_count: 2, kit_types: ["home"])
      %{kits: kits, ranking: ranking_with(kits)}
    end

    test "der Bearbeiten-Link zeigt den Teilen-Link", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/edit")

      assert html =~ "/r/#{r.share_slug}"
      # Der geheime Token darf nicht im sichtbaren Teilen-Feld auftauchen.
      refute html =~ ~s(data-copy=") <> r.edit_token
    end

    test "die öffentliche Ansicht zeigt Reihenfolge und Notizen", %{
      conn: conn,
      ranking: r,
      kits: [a, b]
    } do
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(r.id, 1), "grausam")
      {:ok, _view, html} = live(conn, ~p"/r/#{r.share_slug}")

      assert html =~ "Testliste"
      assert html =~ "grausam"
      assert html =~ Kits.get_team!(a.team_id).name
      assert html =~ Kits.get_team!(b.team_id).name
    end

    test "die öffentliche Ansicht lässt nichts ändern", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/r/#{r.share_slug}")

      refute html =~ ~s(phx-click="move")
      refute html =~ ~s(phx-click="remove")
      refute html =~ ~s(phx-hook="Sortable")
      refute html =~ r.edit_token
    end

    test "zeigt immer den aktuellen Stand, ohne Veröffentlichen-Schritt", %{
      conn: conn,
      ranking: r,
      kits: [a, b]
    } do
      :ok = Rankings.reorder(r, [b.id, a.id])
      {:ok, _view, html} = live(conn, ~p"/r/#{r.share_slug}")

      b_name = Kits.get_team!(b.team_id).name
      a_name = Kits.get_team!(a.team_id).name
      assert :binary.match(html, b_name) < :binary.match(html, a_name)
    end
  end

  describe "Zugriff" do
    test "unbekannte Links sind 404, kein Serverfehler", %{conn: conn} do
      assert_raise KitrankWeb.NotFoundError, fn -> live(conn, ~p"/r/gibtsnicht") end
      assert_raise KitrankWeb.NotFoundError, fn -> live(conn, ~p"/rankings/gibtsnicht/edit") end
    end

    test "der Share-Slug öffnet die Bearbeitung nicht", %{conn: conn} do
      %{kits: kits} = league(team_count: 1, kit_types: ["home"])
      r = ranking_with(kits)

      assert_raise KitrankWeb.NotFoundError, fn ->
        live(conn, ~p"/rankings/#{r.share_slug}/edit")
      end
    end

    test "der Edit-Token öffnet die öffentliche Ansicht nicht", %{conn: conn} do
      r = ranking_with([])

      assert_raise KitrankWeb.NotFoundError, fn -> live(conn, ~p"/r/#{r.edit_token}") end
    end
  end
end
