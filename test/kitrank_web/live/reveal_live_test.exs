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
end
