defmodule KitrankWeb.RegistrationGateTest do
  @moduledoc """
  Die Registrierung ist vollständig gebaut, aber zu. Beides wird hier geprüft:
  dass sie zu ist, und dass das Aufmachen wirklich nur ein Schalter ist.
  """
  use KitrankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # Laeuft nicht async: die Tests schalten global um. Sync-Tests laufen nach
  # allen async-Tests, damit kommt sich das mit den Registrierungs-Tests nicht
  # in die Quere.
  setup do
    original = Application.get_env(:kitrank, :registration_open, false)
    on_exit(fn -> Application.put_env(:kitrank, :registration_open, original) end)
    :ok
  end

  test "geschlossen: die Registrierung leitet zur Anmeldung", %{conn: conn} do
    Application.put_env(:kitrank, :registration_open, false)

    assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
             live(conn, ~p"/users/register")

    assert flash["info"] =~ "nicht offen"
  end

  test "offen: die Registrierung ist erreichbar", %{conn: conn} do
    Application.put_env(:kitrank, :registration_open, true)

    assert {:ok, _view, html} = live(conn, ~p"/users/register")
    assert html =~ "Konto anlegen"
  end

  test "das Konto-Angebot am Gate zeigt sich nur bei offener Registrierung", %{conn: conn} do
    # Ein Link auf eine geschlossene Registrierung waere eine Sackgasse — der
    # Hinweis haengt deshalb am selben Schalter wie die Registrierung selbst.
    %{kits: kits} =
      Kitrank.KitsFixtures.league_fixture(
        season: Kitrank.Kits.current_season(),
        team_count: 1,
        kit_types: ["home"]
      )

    {:ok, ranking} = Kitrank.Rankings.create_ranking(%{display_name: "Geteilt"})
    Kitrank.Rankings.add_kits(ranking, Enum.map(kits, & &1.id))
    {:ok, ranking} = Kitrank.Rankings.set_share_mode(ranking, "gated")

    Application.put_env(:kitrank, :registration_open, false)
    {:ok, view, _html} = live(conn, ~p"/r/#{ranking.share_slug}")
    refute render_hook(view, "remembered_rankings", %{"tokens" => []}) =~ "Mit einem Konto"

    Application.put_env(:kitrank, :registration_open, true)
    {:ok, view, _html} = live(conn, ~p"/r/#{ranking.share_slug}")
    assert render_hook(view, "remembered_rankings", %{"tokens" => []}) =~ "Mit einem Konto"
  end

  test "die Anmeldung ist unabhängig davon immer erreichbar", %{conn: conn} do
    Application.put_env(:kitrank, :registration_open, false)

    assert {:ok, _view, _html} = live(conn, ~p"/users/log-in")
  end
end
