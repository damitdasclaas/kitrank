defmodule KitrankWeb.Admin.AccessTest do
  @moduledoc """
  Wer darf in den Admin-Bereich – und wer ausdrücklich nicht.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.AccountsFixtures

  @admin_paths [
    "/admin",
    "/admin/sportarten",
    "/admin/ligen",
    "/admin/vereine",
    "/admin/saison",
    "/admin/trikots"
  ]

  describe "ohne Anmeldung" do
    test "führt jeder Admin-Pfad zur Anmeldung", %{conn: conn} do
      for path <- @admin_paths do
        assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
      end
    end
  end

  describe "als normaler Nutzer" do
    setup :register_and_log_in_user

    test "bleibt der Admin-Bereich zu", %{conn: conn} do
      for path <- @admin_paths do
        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
        assert flash["error"] =~ "nicht für dich freigegeben"
      end
    end

    test "taucht der Admin-Link nicht im Header auf", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ ~s(href="/admin")
    end
  end

  describe "als Admin" do
    setup %{conn: conn} do
      admin = admin_fixture()
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "öffnet sich jeder Admin-Bereich", %{conn: conn} do
      for path <- @admin_paths do
        assert {:ok, _view, html} = live(conn, path)
        assert html =~ "Admin"
      end
    end

    test "führt der Header in den Admin-Bereich", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(href="/admin")
    end
  end
end
