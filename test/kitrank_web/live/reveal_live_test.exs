defmodule KitrankWeb.RevealLiveTest do
  @moduledoc """
  Der Reveal-Raum von außen: beitreten, warten, gemeinsam aufdecken — und
  besonders, dass zwei Browser wirklich dasselbe sehen.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures
  import Kitrank.RankingsFixtures

  alias Kitrank.Kits
  alias Kitrank.Rankings
  alias Kitrank.Reveal

  defp ranking_with(count) do
    %{kits: kits} =
      league_fixture(season: Kits.current_season(), team_count: count, kit_types: ["home"])

    ranking_with_kits_fixture(kits)
  end

  defp room_fixture(attrs \\ %{}) do
    {:ok, room} = Reveal.create_room(attrs)
    room
  end

  # Der Host wird nicht ueber die Adresse erkannt, sondern ueber ein Token aus
  # dem Browser – im Test also ueber den Hook-Event.
  defp as_host(view, room) do
    render_hook(view, "claim_host", %{"token" => room.host_token})
    view
  end

  describe "Raum anlegen" do
    test "zeigt den Code und legt das Host-Token im Browser ab", %{conn: conn} do
      # Ohne Liga gibt es keinen Ausschnitt zu waehlen – und ohne Ausschnitt
      # laesst die Oberflaeche keinen Raum anlegen.
      %{competition: competition} =
        league_fixture(season: Kits.current_season(), team_count: 1, kit_types: ["home"])

      {:ok, view, _html} = live(conn, ~p"/reveal/new")

      html =
        view
        |> form(~s{form[phx-submit="create"]}, %{"max_participants" => "4"})
        |> render_submit()

      assert html =~ ~s(phx-hook="RememberHost")
      assert [room] = Kitrank.Repo.all(Reveal.Room)
      assert room.max_participants == 4
      assert room.competition_ids == [competition.id]
      assert room.kit_types == ["home"]
      assert html =~ room.room_code
      assert html =~ ~s(data-host-token="#{room.host_token}")
    end
  end

  describe "Zugang" do
    test "unbekannte und abgelaufene Räume sind 404", %{conn: conn} do
      assert_raise KitrankWeb.NotFoundError, fn -> live(conn, ~p"/reveal/ZZZZZ") end

      room = room_fixture()
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      Kitrank.Repo.update_all(Reveal.Room, set: [expires_at: past])

      assert_raise KitrankWeb.NotFoundError, fn -> live(conn, ~p"/reveal/#{room.room_code}") end
    end

    test "der Raumcode allein gibt keine Steuerung", %{conn: conn} do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(2).share_slug, "Tom")

      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      refute html =~ "Du steuerst"
      refute html =~ ~s(phx-click="reveal_next")
    end

    test "ein falsches Host-Token wird verworfen", %{conn: conn} do
      room = room_fixture()
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      render_hook(view, "claim_host", %{"token" => "erfunden"})

      assert_push_event(view, "forget_host", %{code: code})
      assert code == room.room_code
      refute render(view) =~ "Du steuerst"
    end

    test "mit dem echten Token erscheint die Steuerung", %{conn: conn} do
      room = room_fixture()
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html = as_host(view, room) |> render()

      assert html =~ "Du steuerst"
      assert html =~ ~s(phx-click="reveal_next")
    end
  end

  describe "Beitreten" do
    setup do
      %{room: room_fixture(%{max_participants: 2}), ranking: ranking_with(3)}
    end

    test "über den Teilen-Link", %{conn: conn, room: room, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join"]}, %{
          "display_name" => "Tom",
          "share_slug" => r.share_slug
        })
        |> render_submit()

      assert html =~ "Tom"
      assert html =~ "(du)"
      assert [%{display_name: "Tom"}] = Reveal.list_participants(room)
    end

    test "auch wenn jemand den ganzen Link einfügt", %{conn: conn, room: room, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join"]}, %{
        "display_name" => "Tom",
        "share_slug" => "https://kitrank.fly.dev/r/#{r.share_slug}/"
      })
      |> render_submit()

      assert [%{display_name: "Tom"}] = Reveal.list_participants(room)
    end

    test "der Bearbeiten-Link funktioniert dafür nicht", %{conn: conn, room: room, ranking: r} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join"]}, %{
          "display_name" => "Tom",
          "share_slug" => r.edit_token
        })
        |> render_submit()

      assert html =~ "kennen wir nicht"
      assert Reveal.list_participants(room) == []
    end

    test "dieselbe Rangliste kommt nicht zweimal rein", %{conn: conn, room: room, ranking: r} do
      {:ok, _} = Reveal.join(room, r.share_slug, "Tom")
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join"]}, %{
          "display_name" => "Tom nochmal",
          "share_slug" => r.share_slug
        })
        |> render_submit()

      assert html =~ "schon dabei"
    end

    test "ein voller Raum sagt das, statt ein Formular zu zeigen", %{conn: conn, room: room} do
      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Tom")
      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Anna")

      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Der Raum ist voll"
    end
  end

  describe "Ohne Vorbereitung beitreten" do
    setup do
      competition = competition_fixture(name: "Bundesliga", tier: 1)

      league_fixture(
        competition: competition,
        season: Kits.current_season(),
        team_count: 4,
        kit_types: ["home"]
      )

      {:ok, room} =
        Reveal.create_room(%{competition_ids: [competition.id], kit_types: ["home"]})

      %{room: room, competition: competition}
    end

    test "bietet den Weg ohne Rangliste an", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Noch keine Rangliste?"
      assert html =~ ~s{phx-submit="join_new"}
    end

    test "legt eine Rangliste mit dem Ausschnitt an", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
        |> render_submit()

      assert [teilnehmer] = Reveal.list_participants(room)
      assert teilnehmer.display_name == "Spontan"
      # Alle vier Trikots des Ausschnitts, ohne dass jemand etwas ausgewaehlt hat.
      assert Rankings.count_entries(teilnehmer.ranking_id) == 4
      # Und direkt danach sortiert man im Raum.
      assert html =~ "Deine Rangliste"
      assert html =~ ~s{phx-click="own_duel_pick"}
    end

    test "sortiert im Raum und speichert nach jeder Antwort", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
      |> render_submit()

      [teilnehmer] = Reveal.list_participants(room)
      vorher = Rankings.list_entries(teilnehmer.ranking_id) |> Enum.map(& &1.kit_id)

      view |> element(~s{button[phx-value-side="new"]}) |> render_click()

      nachher = Rankings.list_entries(teilnehmer.ranking_id) |> Enum.map(& &1.kit_id)
      assert Enum.sort(nachher) == Enum.sort(vorher)
      refute nachher == vorher
    end

    test "meldet, wenn es im Ausschnitt nichts gibt", %{conn: conn} do
      leer = competition_fixture(name: "Leere Liga", tier: 9)
      {:ok, room} = Reveal.create_room(%{competition_ids: [leer.id], kit_types: ["home"]})

      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
        |> render_submit()

      assert html =~ "keine Trikots"
      assert Reveal.list_participants(room) == []
    end

    test "der Weg mit Teilen-Link bleibt daneben", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Teilen-Link"
      assert html =~ ~s{phx-submit="join"}
    end

    test "der Browser merkt sich die neue Rangliste", %{conn: conn, room: room} do
      # Vorher stand ihr Bearbeiten-Token nur in den Socket-Assigns: Tab zu und
      # die Rangliste war unerreichbar — sie lag in der Datenbank, aber niemand
      # kam mehr hin.
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
        |> render_submit()

      assert html =~ ~s{id="remember-room-ranking"}
      assert html =~ ~s{phx-hook="RememberRanking"}

      [teilnehmer] = Reveal.list_participants(room)
      ranking = Kitrank.Repo.get!(Kitrank.Rankings.Ranking, teilnehmer.ranking_id)

      assert html =~ ranking.edit_token
      assert html =~ "/rankings/#{ranking.edit_token}/edit"
      assert html =~ "Geheim halten"
    end

    test "merkt sich den Token einer fremden Rangliste nicht", %{conn: conn, room: room} do
      # Der Fall, der still gefährlich wäre: wer mit dem Teilen-Link einer
      # fremden Rangliste beitritt, dürfte deren *Bearbeiten*-Token nicht
      # gemerkt bekommen — aus einem öffentlichen Link würde Schreibrecht.
      fremd = ranking_with(2)

      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join"]}, %{
          "share_slug" => fremd.share_slug,
          "display_name" => "Anna"
        })
        |> render_submit()

      refute html =~ fremd.edit_token
      refute html =~ ~s{id="remember-room-ranking"}
    end

    test "nach dem Duell sieht man die Reihenfolge und kann sie ändern", %{
      conn: conn,
      room: room
    } do
      # Vorher stand dort nur ein Satz. Man sah nicht einmal, was
      # herausgekommen ist.
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
      |> render_submit()

      html = duell_durchklicken(view)

      assert html =~ ~s{phx-click="own_move"}
      assert html =~ "Nochmal vergleichen"
      assert html =~ "Wenn der Host startet"
    end

    test "ein Pfeilklick verschiebt wirklich", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
      |> render_submit()

      duell_durchklicken(view)

      [teilnehmer] = Reveal.list_participants(room)
      vorher = Rankings.list_entries(teilnehmer.ranking_id) |> Enum.map(& &1.kit_id)

      render_click(view, "own_move", %{"kit" => to_string(Enum.at(vorher, 1)), "delta" => "-1"})

      nachher = Rankings.list_entries(teilnehmer.ranking_id) |> Enum.map(& &1.kit_id)

      assert Enum.take(nachher, 2) == [Enum.at(vorher, 1), Enum.at(vorher, 0)]
    end

    test "die Duell-Bilder tragen eine Kennung, die am Trikot hängt", %{conn: conn, room: room} do
      # Ohne sie ändert LiveView nur das src am vorhandenen Element, und der
      # Browser zeigt das alte Bild weiter, bis das neue geladen ist — dann
      # sieht man zweimal dasselbe Trikot.
      #
      # Trikots mit Bild: ohne Bild zeichnet kit_figure die Silhouette, und dann
      # gibt es kein <img>, an dem eine Kennung hängen könnte.
      for kit <- Kits.list_kits(Kits.current_season()) do
        {:ok, _} =
          Kits.update_kit(kit, %{
            "cutout_url" => "https://cdn.shopify.com/s/#{kit.id}.jpg"
          })
      end

      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      html =
        view
        |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
        |> render_submit()

      treffer = Regex.scan(~r/id="raumduell-bild-(new|existing)-(\d+)"/, html)

      assert length(treffer) == 2, "beide Duell-Bilder brauchen eine eigene Kennung"

      [[_, _, links], [_, _, rechts]] = treffer
      assert links != rechts

      # Und sie laden sofort – im Duell sind sie der Grund der Seite.
      assert html =~ ~s{loading="eager"}
      assert html =~ ~s{fetchpriority="high"}
    end

    test "Pfeiltasten sortieren auch", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join_new"]}, %{"display_name" => "Spontan"})
      |> render_submit()

      html = view |> element("#eigenes-duell") |> render_keydown(%{"key" => "ArrowRight"})

      assert html =~ "von 4 eingeordnet"
    end
  end

  describe "Aufdecken" do
    setup do
      room = room_fixture()
      {:ok, tom} = Reveal.join(room, ranking_with(3).share_slug, "Tom")
      {:ok, anna} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
      %{room: room, tom: tom, anna: anna}
    end

    test "startet beim schlechtesten Rang der längsten Liste", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view |> element(~s{button[phx-click="reveal_next"]}) |> render_click()

      # Der Schritt kommt ueber PubSub zurueck – auch beim Host selbst, damit
      # alle garantiert denselben Stand rendern.
      html = render(view)
      assert html =~ "Platz 3"
      assert html =~ "Tom"
      assert html =~ "Anna"
    end

    test "kürzere Listen zeigen eine leere Karte statt zu verschwinden", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view |> element(~s{button[phx-click="reveal_next"]}) |> render_click()

      assert render(view) =~ "Liste reicht nicht so weit"
    end

    test "zählt runter und schließt ab", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)
      knopf = ~s{button[phx-click="reveal_next"]}

      view |> element(knopf) |> render_click()
      assert render(view) =~ "Nächster Platz"

      view |> element(knopf) |> render_click()
      assert render(view) =~ "Platz 2"

      view |> element(knopf) |> render_click()
      html = render(view)
      assert html =~ "Platz 1"
      assert html =~ "Abschließen"

      view |> element(knopf) |> render_click()
      html = render(view)
      assert html =~ "Fertig"
      # Nach dem Abschluss verschwindet die Steuerung.
      refute html =~ "Nächster Platz"
    end

    test "zeigt die Notiz zum jeweiligen Rang", %{conn: conn, room: room, tom: tom} do
      {:ok, _} =
        Rankings.update_note(Rankings.get_entry_at(tom.ranking_id, 3), "ganz unten, klar")

      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view |> element(~s{button[phx-click="reveal_next"]}) |> render_click()
      # Die Notiz steht hinter Toms verdeckter Karte, bis er selbst aufdeckt.
      refute render(view) =~ "ganz unten, klar"

      {:ok, gestartet} = Reveal.fetch_room(room.room_code)
      {:ok, _} = Reveal.reveal_own(gestartet, tom.id)

      assert render(view) =~ "ganz unten, klar"
    end

    test "beide Browser sehen denselben Schritt", %{conn: conn, room: room} do
      {:ok, host, _} = live(conn, ~p"/reveal/#{room.room_code}")
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(host, room)

      # Der Gast hat keine Steuerung ...
      refute render(gast) =~ ~s(phx-click="reveal_next")

      # ... sieht den Schritt des Hosts aber sofort.
      host |> element(~s{button[phx-click="reveal_next"]}) |> render_click()

      assert render(gast) =~ "Platz 3"
      assert render(gast) =~ "Tom"
    end

    test "ein Beitritt taucht bei allen auf", %{conn: conn, room: room} do
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")
      refute render(gast) =~ "Späti"

      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Späti")

      assert render(gast) =~ "Späti"
    end

    test "ohne Steuerung passiert beim Weiterschalten nichts", %{conn: conn, room: room} do
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")

      render_hook(gast, "reveal_next", %{})

      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.status == "waiting"
    end
  end

  describe "Selbst aufdecken" do
    setup do
      room = room_fixture()
      {:ok, tom} = Reveal.join(room, ranking_with(2).share_slug, "Tom")
      {:ok, anna} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
      {:ok, room} = Reveal.start(room)
      %{room: room, tom: tom, anna: anna}
    end

    test "Karten liegen erst verdeckt", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "deckt noch auf"
      refute html =~ ~s(phx-click="reveal_own")
    end

    test "nur die eigene Karte hat einen Aufdecken-Knopf", %{conn: conn} do
      # Eigener Raum: dieser Browser tritt wirklich als Tom bei, damit der
      # LiveView weiss, wer er ist.
      room = room_fixture()
      {:ok, _anna} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
      toms_liste = ranking_with(2)

      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")

      view
      |> form(~s{form[phx-submit="join"]}, %{
        "display_name" => "Tom",
        "share_slug" => toms_liste.share_slug
      })
      |> render_submit()

      {:ok, _room} = Reveal.start(room)

      html = render(view)
      # Genau einer – Annas Karte bleibt ohne Knopf.
      assert length(Regex.scan(~r/phx-click="reveal_own"/, html)) == 1
      assert html =~ "Anna deckt noch auf"
    end

    test "aufdecken zeigt das eigene Trikot bei allen", %{conn: conn, room: room, tom: tom} do
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")
      assert render(gast) =~ "deckt noch auf"

      {:ok, _} = Reveal.reveal_own(room, tom.id)

      html = render(gast)
      assert html =~ "Tom"
      # Anna liegt weiterhin verdeckt.
      assert html =~ "Anna deckt noch auf"
    end

    test "leere Karten gelten als aufgedeckt – sonst wartet die Runde ewig" do
      room = room_fixture()
      {:ok, _lang} = Reveal.join(room, ranking_with(3).share_slug, "Lang")
      {:ok, kurz} = Reveal.join(room, ranking_with(1).share_slug, "Kurz")
      {:ok, room} = Reveal.start(room)

      eintrag = Reveal.step_entries(room) |> Enum.find(&(&1.participant_id == kurz.id))
      assert eintrag.kit == nil
      assert eintrag.revealed?
    end

    test "alle aufgedeckt wird gemeldet", %{room: room, tom: tom, anna: anna} do
      assert Reveal.reveal_progress(room) == {0, 2}
      refute Reveal.all_revealed?(room)

      {:ok, _} = Reveal.reveal_own(room, tom.id)
      assert Reveal.reveal_progress(room) == {1, 2}

      {:ok, _} = Reveal.reveal_own(room, anna.id)
      assert Reveal.all_revealed?(room)
    end

    test "der nächste Platz liegt wieder verdeckt", %{room: room, tom: tom} do
      {:ok, _} = Reveal.reveal_own(room, tom.id)
      {:ok, room} = Reveal.reveal_next(room)

      refute Reveal.all_revealed?(room)
      assert Reveal.reveal_progress(room) == {0, 2}
    end

    test "der Host kann weiterschalten, auch wenn nicht alle aufgedeckt haben", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view |> element(~s{button[phx-click="reveal_next"]}) |> render_click()

      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.current_step == 1
    end

    test "wer nicht mitspielt, kann nichts aufdecken", %{conn: conn, room: room} do
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")

      render_hook(gast, "reveal_own", %{})

      assert Reveal.reveal_progress(room) == {0, 2}
      assert render(gast) =~ "Du schaust nur zu"
    end
  end

  describe "Auswertung am Ende" do
    setup do
      %{kits: kits} =
        league_fixture(season: Kits.current_season(), team_count: 3, kit_types: ["home"])

      [a, b, c] = kits

      tom_liste = ranking_with_kits_fixture([a, b, c])
      anna_liste = ranking_with_kits_fixture([c, b, a])

      room = room_fixture()
      {:ok, tom} = Reveal.join(room, tom_liste.share_slug, "Tom")
      {:ok, anna} = Reveal.join(room, anna_liste.share_slug, "Anna")
      {:ok, room} = Reveal.start(room)

      %{room: room, tom: tom, anna: anna, kits: kits, tom_liste: tom_liste}
    end

    defp durchlaufen(room) do
      Enum.reduce_while(1..20, room, fn _, acc ->
        {:ok, acc} = Reveal.reveal_next(acc)
        if acc.status == "done", do: {:halt, acc}, else: {:cont, acc}
      end)
    end

    test "erscheint erst am Ende, nicht vorher", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")
      refute html =~ "Wie einig wart ihr?"

      durchlaufen(room)

      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")
      assert html =~ "Wie einig wart ihr?"
    end

    test "zeigt den größten Streitfall mit Namen und Plätzen", %{conn: conn, room: room} do
      durchlaufen(room)
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Größter Streitfall"
      assert html =~ "2 Plätze Unterschied"
      assert html =~ "Tom"
      assert html =~ "Anna"
    end

    test "zeigt den Abstand zwischen den Personen", %{conn: conn, room: room} do
      durchlaufen(room)
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Wer liegt beieinander"
      # Genau umgekehrte Listen bei drei Trikots: (2+0+2)/3 ≈ 1,3
      assert html =~ "1.3 Plätze auseinander"
    end

    test "sammelt die Notizen mit Person und Platz", %{conn: conn, room: room, tom_liste: liste} do
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(liste.id, 1), "mein Favorit")
      durchlaufen(room)

      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Was gesagt wurde"
      assert html =~ "mein Favorit"
      assert html =~ "Platz 1"
    end

    test "bleibt über den Raumcode erreichbar", %{conn: conn, room: room} do
      durchlaufen(room)
      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ room.room_code
      assert html =~ "zeigt weiterhin diese Auswertung"
    end

    test "sagt es, wenn es keine Überschneidung gab", %{conn: conn} do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(2).share_slug, "Tom")
      {:ok, _} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
      {:ok, room} = Reveal.start(room)
      durchlaufen(room)

      {:ok, _view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "kein einziges Trikot gemeinsam"
    end
  end

  describe "Gesamtübersicht" do
    setup do
      room = room_fixture()
      {:ok, tom} = Reveal.join(room, ranking_with(3).share_slug, "Tom")
      {:ok, anna} = Reveal.join(room, ranking_with(3).share_slug, "Anna")
      {:ok, room} = Reveal.start(room)
      %{room: room, tom: tom, anna: anna}
    end

    test "zeigt eine Zeile je bisher offenem Platz", %{room: room, tom: tom} do
      board = Reveal.revealed_board(room)
      assert Enum.map(board.rows, & &1.step) == [3]
      assert Enum.map(board.participants, & &1.name) == ["Tom", "Anna"]

      {:ok, _} = Reveal.reveal_own(room, tom.id)
      {:ok, room} = Reveal.reveal_next(room)

      assert Reveal.revealed_board(room) |> Map.fetch!(:rows) |> Enum.map(& &1.step) == [3, 2]
    end

    test "verdeckte Karten der laufenden Runde bleiben verdeckt", %{room: room, tom: tom} do
      {:ok, _} = Reveal.reveal_own(room, tom.id)

      [zeile] = Reveal.revealed_board(room).rows
      sichtbar = Map.new(zeile.cells, &{&1.participant_id, &1.visible?})

      assert sichtbar[tom.id]
      refute Enum.all?(Map.values(sichtbar))
    end

    test "vergangene Runden sind offen, auch wenn jemand nie geklickt hat", %{
      room: room,
      anna: anna
    } do
      # Niemand deckt auf, der Host schaltet trotzdem weiter.
      {:ok, room} = Reveal.reveal_next(room)

      board = Reveal.revealed_board(room)
      alt = Enum.find(board.rows, &(&1.step == 3))
      annas_zelle = Enum.find(alt.cells, &(&1.participant_id == anna.id))

      assert annas_zelle.visible?, "die vorige Runde ist vorbei und damit offen"
    end

    test "steht im Raum und lässt sich zuklappen", %{conn: conn, room: room} do
      {:ok, view, html} = live(conn, ~p"/reveal/#{room.room_code}")

      assert html =~ "Gesamtübersicht"
      assert html =~ "<table"

      html = view |> element(~s{button[phx-click="toggle_board"]}) |> render_click()
      refute html =~ "<table"
    end
  end

  describe "Beitreten per Code" do
    test "führt in den Raum", %{conn: conn} do
      room = room_fixture()
      {:ok, view, _html} = live(conn, ~p"/reveal/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form(~s{form[phx-submit="join"]}, %{"room_code" => room.room_code})
               |> render_submit()

      assert to == "/reveal/#{room.room_code}"
    end

    test "nimmt den Code auch klein geschrieben", %{conn: conn} do
      room = room_fixture()
      {:ok, view, _html} = live(conn, ~p"/reveal/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form(~s{form[phx-submit="join"]}, %{
                 "room_code" => String.downcase(room.room_code)
               })
               |> render_submit()

      assert to == "/reveal/#{room.room_code}"
    end

    test "sagt Bescheid, wenn es den Code nicht gibt", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reveal/new")

      html =
        view |> form(~s{form[phx-submit="join"]}, %{"room_code" => "ZZZZZ"}) |> render_submit()

      assert html =~ "Vertippt?"
    end
  end

  describe "Steuerung übergeben" do
    setup do
      room = room_fixture()
      {:ok, tom} = Reveal.join(room, ranking_with(2).share_slug, "Tom")
      %{room: room, tom: tom}
    end

    test "der Host gibt sie an einen Teilnehmer ab", %{conn: conn, room: room, tom: tom} do
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view
      |> element(~s{button[phx-click="transfer_host"][phx-value-id="#{tom.id}"]})
      |> render_click()

      assert render(view) =~ "steuert"
      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.host_participant_id == tom.id
    end

    test "der neue Host bekommt die Steuerung in seinem Browser", %{
      conn: conn,
      room: room,
      tom: tom
    } do
      {:ok, toms_view, _} = live(conn, ~p"/reveal/#{room.room_code}")

      # Tom tritt in diesem Browser bei und ist danach er selbst.
      {:ok, ranking} = Rankings.create_ranking(%{})
      {:ok, _} = Rankings.add_kit(ranking, hd(Rankings.list_entries(tom.ranking_id)).kit_id)

      {:ok, _room} = Reveal.transfer_host(room, tom.id)

      # Ein Browser, der als Tom beigetreten ist, steuert jetzt.
      assert Reveal.host?(elem(Reveal.fetch_room(room.room_code), 1), nil, tom.id)
      assert render(toms_view) =~ room.room_code
    end

    test "der Ersteller kann sie zurückholen", %{conn: conn, room: room, tom: tom} do
      {:ok, _room} = Reveal.transfer_host(room, tom.id)
      {:ok, view, _html} = live(conn, ~p"/reveal/#{room.room_code}")
      as_host(view, room)

      view |> element(~s{button[phx-click="reclaim_host"]}) |> render_click()

      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.host_participant_id == nil
    end

    test "wer nicht steuert, kann auch nicht übergeben", %{conn: conn, room: room, tom: tom} do
      {:ok, gast, _} = live(conn, ~p"/reveal/#{room.room_code}")

      render_hook(gast, "transfer_host", %{"id" => to_string(tom.id)})

      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.host_participant_id == nil
    end
  end

  # Solange das Duell fragt, immer die linke Seite waehlen.
  defp duell_durchklicken(view, runden \\ 40) do
    html = render(view)

    if runden > 0 and html =~ ~s{phx-click="own_duel_pick"} do
      render_click(view, "own_duel_pick", %{"side" => "new"})
      duell_durchklicken(view, runden - 1)
    else
      html
    end
  end
end
