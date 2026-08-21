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
    assert html =~ "Register"
  end

  test "die Anmeldung ist unabhängig davon immer erreichbar", %{conn: conn} do
    Application.put_env(:kitrank, :registration_open, false)

    assert {:ok, _view, _html} = live(conn, ~p"/users/log-in")
  end
end
