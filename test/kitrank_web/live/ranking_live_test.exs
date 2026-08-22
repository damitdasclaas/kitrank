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

    test "nimmt eine ganze Liga auf und wieder heraus", %{
      conn: conn,
      ranking: r,
      competition: competition,
      kits: kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-click="toggle_competition"][phx-value-id="#{competition.id}"]})
        |> render_click()

      assert Rankings.count_entries(r.id) == length(kits)
      assert html =~ "Alle abwählen"

      view
      |> element(~s{button[phx-click="toggle_competition"][phx-value-id="#{competition.id}"]})
      |> render_click()

      assert Rankings.count_entries(r.id) == 0
    end

    test "behält die Notiz, wenn eine Liga nochmal komplett hinzugefügt wird", %{
      conn: conn,
      ranking: r,
      competition: competition,
      kits: [kit | _]
    } do
      {:ok, _} = Rankings.add_kit(r, kit.id)
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(r.id, 1), "wichtig")

      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="toggle_competition"][phx-value-id="#{competition.id}"]})
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

  describe "Liga-Vorauswahl" do
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

    test "zeigt anfangs alle Ligen, solange nichts gewählt ist", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ "Welche Ligen?"
      assert html =~ "Erste Liga"
      assert html =~ "Zweite Liga"
      assert html =~ "Schnell auswählen"
    end

    test "blendet abgewählte Ligen aus dem Raster aus", %{
      conn: conn,
      ranking: r,
      zweite: zweite,
      zweite_kits: [kit | _]
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html =
        view
        |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{zweite.id}"]})
        |> render_click()

      refute html =~ ~s{phx-click="toggle_kit" phx-value-id="#{kit.id}"}
    end

    test "ohne Liga gibt es nichts auszuwählen", %{conn: conn, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      html = view |> element(~s{button[phx-click="no_leagues"]}) |> render_click()

      assert html =~ "Erst eine Liga wählen"
      refute html =~ "Schnell auswählen"
    end

    test "kommt man wieder, sind die Ligen der bisherigen Auswahl aktiv", %{
      conn: conn,
      ranking: r,
      erste_kits: [kit | _],
      zweite_kits: [fremd | _]
    } do
      {:ok, _} = Rankings.add_kit(r, kit.id)

      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ ~s{phx-value-id="#{kit.id}"}
      refute html =~ ~s{phx-click="toggle_kit" phx-value-id="#{fremd.id}"}
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
        zweite: zweite,
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

    test "wirkt nur auf die vorgewählten Ligen", %{
      conn: conn,
      ranking: r,
      zweite: zweite,
      zweite_kits: zweite_kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      # Zweite Liga abwählen, dann alle Heimtrikots nehmen.
      view
      |> element(~s{button[phx-click="toggle_league"][phx-value-id="#{zweite.id}"]})
      |> render_click()

      view
      |> element(~s{button[phx-click="quick_select"][phx-value-type="home"]})
      |> render_click()

      gewaehlt = Rankings.list_entries(r) |> Enum.map(& &1.kit_id) |> MapSet.new()
      assert Rankings.count_entries(r.id) == 2

      for kit <- zweite_kits do
        refute MapSet.member?(gewaehlt, kit.id), "Trikot aus der abgewählten Liga ist drin"
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

    test "'Alle Trikots' nimmt alles aus den vorgewählten Ligen", %{
      conn: conn,
      ranking: r,
      erste_kits: erste_kits,
      zweite_kits: zweite_kits
    } do
      {:ok, view, _html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      view
      |> element(~s{button[phx-click="quick_select"][phx-value-type="all"]})
      |> render_click()

      assert Rankings.count_entries(r.id) == length(erste_kits) + length(zweite_kits)
    end

    test "bietet keinen Knopf für Kit-Typen an, die es nicht gibt", %{conn: conn, ranking: r} do
      {:ok, _view, html} = live(conn, ~p"/rankings/#{r.edit_token}/auswahl")

      assert html =~ ~s{phx-value-type="home"}
      assert html =~ ~s{phx-value-type="away"}
      refute html =~ ~s{phx-value-type="third"}
      refute html =~ ~s{phx-value-type="special"}
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

      html = view |> element(~s{#entry-detail button[aria-label="Schliessen"]}) |> render_click()

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
