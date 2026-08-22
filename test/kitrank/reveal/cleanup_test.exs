defmodule Kitrank.Reveal.CleanupTest do
  @moduledoc """
  Räume laufen ab und müssen auch wirklich verschwinden — sonst wächst die
  Tabelle still weiter.
  """
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures
  import Kitrank.RankingsFixtures

  alias Kitrank.Rankings
  alias Kitrank.Repo
  alias Kitrank.Reveal
  alias Kitrank.Reveal.Cleanup
  alias Kitrank.Reveal.Room

  # Eigene Instanz statt der aus dem Supervision-Tree: die kennt die Datenbank
  # dieses Tests nicht.
  defp cleanup_process(opts \\ []) do
    name = :"cleanup_#{System.unique_integer([:positive])}"

    opts =
      Keyword.merge(
        [name: name, interval: :timer.hours(24), initial_delay: :timer.hours(24)],
        opts
      )

    pid = start_supervised!({Cleanup, opts}, id: name)
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    {name, pid}
  end

  defp abgelaufen(room) do
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(r in Room, where: r.id == ^room.id), set: [expires_at: past])
    room
  end

  test "löscht abgelaufene Räume und lässt aktive stehen" do
    {:ok, aktiv} = Reveal.create_room()
    {:ok, alt} = Reveal.create_room()
    abgelaufen(alt)

    {name, _pid} = cleanup_process()
    assert Cleanup.run_now(name) == 1

    assert {:ok, _} = Reveal.fetch_room(aktiv.room_code)
    assert Reveal.fetch_room(alt.room_code) == {:error, :not_found}
  end

  test "nimmt die Teilnahmen mit, aber nicht die Ranglisten" do
    %{kits: kits} = league_fixture(team_count: 1, kit_types: ["home"])
    ranking = ranking_with_kits_fixture(kits)

    {:ok, room} = Reveal.create_room()
    {:ok, _} = Reveal.join(room, ranking.share_slug, "Tom")
    abgelaufen(room)

    {name, _pid} = cleanup_process()
    assert Cleanup.run_now(name) == 1

    # Die Rangliste ist mehr als ihre Teilnahme an einem Abend.
    assert Rankings.get_ranking_by_share_slug(ranking.share_slug)
    assert Rankings.count_entries(ranking.id) == 1
  end

  test "tut nichts, wenn es nichts zu tun gibt" do
    {:ok, _} = Reveal.create_room()

    {name, _pid} = cleanup_process()
    assert Cleanup.run_now(name) == 0
  end

  test "räumt von allein auf und läuft danach weiter" do
    {:ok, alt} = Reveal.create_room()
    abgelaufen(alt)

    {name, pid} = cleanup_process(interval: 50, initial_delay: 10)

    # Der erste Durchgang kommt ohne Zutun.
    assert eventually(fn -> Reveal.fetch_room(alt.room_code) == {:error, :not_found} end)

    # Und der Prozess lebt weiter, statt nach einem Mal fertig zu sein.
    assert Process.alive?(pid)
    assert Cleanup.run_now(name) == 0
  end

  defp eventually(fun, versuche \\ 40) do
    cond do
      fun.() -> true
      versuche == 0 -> false
      true -> Process.sleep(25) && eventually(fun, versuche - 1)
    end
  end
end
