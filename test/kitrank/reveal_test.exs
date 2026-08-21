defmodule Kitrank.RevealTest do
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures
  import Kitrank.RankingsFixtures

  alias Kitrank.Rankings
  alias Kitrank.Repo
  alias Kitrank.Reveal
  alias Kitrank.Reveal.Room

  defp room_fixture(attrs \\ %{}) do
    {:ok, room} = Reveal.create_room(attrs)
    room
  end

  # Eine Rangliste mit `count` Trikots – die Trikots sind pro Aufruf eigene,
  # damit sich die Listen zweier Teilnehmer nicht überschneiden müssen.
  defp ranking_with(count) do
    %{kits: kits} = league_fixture(team_count: count, kit_types: ["home"])
    ranking_with_kits_fixture(kits)
  end

  describe "create_room/1" do
    test "vergibt Raumcode, Host-Token und Ablaufzeit" do
      room = room_fixture()

      assert String.length(room.room_code) == 5
      assert room.room_code == String.upcase(room.room_code)
      assert String.length(room.host_token) == 32
      assert room.status == "waiting"
      assert room.max_participants == 8
      assert DateTime.compare(room.expires_at, DateTime.utc_now()) == :gt
    end

    test "verwendet keine leicht zu verwechselnden Zeichen im Code" do
      for _ <- 1..25 do
        room = room_fixture()
        refute room.room_code =~ ~r/[IO01]/
      end
    end
  end

  describe "fetch_room/1" do
    test "findet den Raum unabhängig von Groß-/Kleinschreibung und Leerzeichen" do
      room = room_fixture()

      assert {:ok, found} = Reveal.fetch_room("  #{String.downcase(room.room_code)} ")
      assert found.id == room.id
    end

    test "unbekannte Codes sind not_found" do
      assert Reveal.fetch_room("ZZZZZ") == {:error, :not_found}
      assert Reveal.fetch_room(nil) == {:error, :not_found}
    end

    test "abgelaufene Räume melden sich als abgelaufen statt still zu funktionieren" do
      room = room_fixture()
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      Repo.update_all(Room, set: [expires_at: past])

      assert Reveal.fetch_room(room.room_code) == {:error, :expired}
    end
  end

  describe "host?/2" do
    test "erkennt nur das echte Host-Token an" do
      room = room_fixture()

      assert Reveal.host?(room, room.host_token)
      refute Reveal.host?(room, room.room_code)
      refute Reveal.host?(room, "falsch")
      refute Reveal.host?(room, nil)
    end

    test "ohne Uebergabe macht kein Teilnehmer den Host" do
      room = room_fixture()
      {:ok, participant} = Reveal.join(room, ranking_with(1).share_slug, "Tom")

      refute Reveal.host?(room, nil, participant.id)
    end
  end

  describe "transfer_host/2" do
    setup do
      room = room_fixture()
      {:ok, tom} = Reveal.join(room, ranking_with(2).share_slug, "Tom")
      {:ok, anna} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
      %{room: room, tom: tom, anna: anna}
    end

    test "gibt die Steuerung an einen Teilnehmer ab", %{room: room, anna: anna} do
      assert {:ok, room} = Reveal.transfer_host(room, anna.id)

      assert Reveal.host?(room, nil, anna.id)
      assert Reveal.designated_host?(room, anna.id)
    end

    test "nimmt dem vorigen Host die uebergebene Rolle", %{room: room, tom: tom, anna: anna} do
      {:ok, room} = Reveal.transfer_host(room, tom.id)
      {:ok, room} = Reveal.transfer_host(room, anna.id)

      refute Reveal.designated_host?(room, tom.id)
      assert Reveal.designated_host?(room, anna.id)
    end

    test "der Ersteller behaelt seinen Schluessel, damit kein Raum haengenbleibt", %{
      room: room,
      anna: anna
    } do
      {:ok, room} = Reveal.transfer_host(room, anna.id)

      assert Reveal.owner?(room, room.host_token)
      assert Reveal.host?(room, room.host_token)
    end

    test "holt der Ersteller die Steuerung zurueck", %{room: room, anna: anna} do
      {:ok, room} = Reveal.transfer_host(room, anna.id)
      assert {:ok, room} = Reveal.reclaim_host(room)

      refute Reveal.designated_host?(room, anna.id)
      assert room.host_participant_id == nil
    end

    test "gibt nichts an Fremde ab", %{room: room} do
      anderer_raum = room_fixture()
      {:ok, fremder} = Reveal.join(anderer_raum, ranking_with(1).share_slug, "Fremd")

      assert {:error, :not_a_participant} = Reveal.transfer_host(room, fremder.id)
      assert {:error, :not_a_participant} = Reveal.transfer_host(room, 999_999)
    end

    test "broadcastet den Wechsel", %{room: room, anna: anna} do
      Reveal.subscribe(room)

      {:ok, _room} = Reveal.transfer_host(room, anna.id)
      assert_receive {:host_changed, host_id}
      assert host_id == anna.id

      {:ok, room} = Reveal.fetch_room(room.room_code)
      {:ok, _room} = Reveal.reclaim_host(room)
      assert_receive {:host_changed, nil}
    end

    test "verliert der Host-Teilnehmer seinen Platz, faellt die Steuerung zurueck", %{
      room: room,
      anna: anna
    } do
      {:ok, room} = Reveal.transfer_host(room, anna.id)
      Repo.delete!(anna)

      {:ok, room} = Reveal.fetch_room(room.room_code)
      assert room.host_participant_id == nil
      assert Reveal.host?(room, room.host_token)
    end
  end

  describe "join/3" do
    test "verknüpft die Rangliste über ihren Share-Slug" do
      room = room_fixture()
      ranking = ranking_with(2)

      assert {:ok, participant} = Reveal.join(room, ranking.share_slug, "Tom")
      assert participant.ranking_id == ranking.id
      assert participant.display_name == "Tom"
    end

    test "das Edit-Token ist kein Beitritts-Schlüssel" do
      room = room_fixture()
      ranking = ranking_with(1)

      assert {:error, :unknown_share_slug} = Reveal.join(room, ranking.edit_token, "Tom")
    end

    test "lehnt unbekannte Slugs ab" do
      assert {:error, :unknown_share_slug} = Reveal.join(room_fixture(), "gibtsnicht", "Tom")
    end

    test "lässt dieselbe Rangliste nicht doppelt beitreten" do
      room = room_fixture()
      ranking = ranking_with(1)

      {:ok, _} = Reveal.join(room, ranking.share_slug, "Tom")
      assert {:error, changeset} = Reveal.join(room, ranking.share_slug, "Tom nochmal")
      assert changeset.errors[:room_id]
    end

    test "achtet auf max_participants" do
      room = room_fixture(%{max_participants: 1})
      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Tom")

      assert {:error, :room_full} = Reveal.join(room, ranking_with(1).share_slug, "Anna")
    end

    test "lässt niemanden mehr rein, wenn das Reveal schon läuft" do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(2).share_slug, "Tom")
      {:ok, room} = Reveal.start(room)

      assert {:error, :already_started} = Reveal.join(room, ranking_with(2).share_slug, "Anna")
    end

    test "broadcastet die geänderte Teilnehmerliste" do
      room = room_fixture()
      Reveal.subscribe(room)

      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Tom")

      assert_receive {:participants_changed, [%{display_name: "Tom"}]}
    end
  end

  describe "start/1" do
    test "startet beim schlechtesten Rang der längsten Liste" do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(3).share_slug, "Tom")
      {:ok, _} = Reveal.join(room, ranking_with(5).share_slug, "Anna")

      assert {:ok, room} = Reveal.start(room)
      assert room.status == "revealing"
      assert room.current_step == 5
    end

    test "startet nicht ohne Einträge" do
      assert {:error, :no_entries} = Reveal.start(room_fixture())
    end
  end

  describe "reveal_next/1" do
    setup do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(3).share_slug, "Tom")
      %{room: room}
    end

    test "startet das Reveal, wenn es noch nicht läuft", %{room: room} do
      assert {:ok, room} = Reveal.reveal_next(room)
      assert room.status == "revealing"
      assert room.current_step == 3
    end

    test "zählt Richtung Rang 1 runter", %{room: room} do
      {:ok, room} = Reveal.start(room)
      {:ok, room} = Reveal.reveal_next(room)
      assert room.current_step == 2

      {:ok, room} = Reveal.reveal_next(room)
      assert room.current_step == 1
      assert room.status == "revealing"
    end

    test "beendet den Raum nach Rang 1 und bleibt dort stehen", %{room: room} do
      {:ok, room} = Reveal.start(room)
      room = Enum.reduce(1..2, room, fn _, acc -> elem(Reveal.reveal_next(acc), 1) end)

      {:ok, room} = Reveal.reveal_next(room)
      assert room.status == "done"
      assert room.current_step == 1

      {:ok, room} = Reveal.reveal_next(room)
      assert room.status == "done"
    end

    test "broadcastet jeden Schritt samt geladener Einträge", %{room: room} do
      Reveal.subscribe(room)
      {:ok, _room} = Reveal.start(room)

      assert_receive {:step_revealed, 3, [%{participant_name: "Tom", kit: kit}]}
      assert kit.id
      # Der Broadcast bringt das Team schon mit, damit kein Client nachlädt.
      assert Ecto.assoc_loaded?(kit.team)
    end
  end

  describe "step_entries/1" do
    test "gibt für kürzere Ranglisten eine leere Karte statt gar nichts" do
      room = room_fixture()
      {:ok, _} = Reveal.join(room, ranking_with(1).share_slug, "Kurz")
      {:ok, _} = Reveal.join(room, ranking_with(3).share_slug, "Lang")

      {:ok, room} = Reveal.start(room)

      entries = Reveal.step_entries(room)
      assert length(entries) == 2

      assert %{participant_name: "Kurz", kit: nil} =
               Enum.find(entries, &(&1.participant_name == "Kurz"))

      assert %{kit: %{}} = Enum.find(entries, &(&1.participant_name == "Lang"))
    end

    test "liefert die Notiz zum jeweiligen Rang mit" do
      room = room_fixture()
      ranking = ranking_with(1)
      {:ok, _} = Rankings.update_note(Rankings.get_entry_at(ranking.id, 1), "grausam")
      {:ok, _} = Reveal.join(room, ranking.share_slug, "Tom")

      {:ok, room} = Reveal.start(room)
      assert [%{note: "grausam"}] = Reveal.step_entries(room)
    end

    test "ist leer, solange der Raum wartet" do
      assert Reveal.step_entries(room_fixture()) == []
    end
  end

  describe "delete_expired_rooms/1" do
    test "räumt nur abgelaufene Räume ab und lässt Ranglisten stehen" do
      aktiv = room_fixture()
      abgelaufen = room_fixture()
      ranking = ranking_with(1)
      {:ok, _} = Reveal.join(abgelaufen, ranking.share_slug, "Tom")

      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      Repo.update_all(from(r in Room, where: r.id == ^abgelaufen.id), set: [expires_at: past])

      assert Reveal.delete_expired_rooms() == 1
      assert {:ok, _} = Reveal.fetch_room(aktiv.room_code)
      assert Reveal.fetch_room(abgelaufen.room_code) == {:error, :not_found}
      assert Rankings.get_ranking_by_share_slug(ranking.share_slug)
    end
  end
end
