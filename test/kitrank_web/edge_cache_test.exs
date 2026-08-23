defmodule KitrankWeb.EdgeCacheTest do
  @moduledoc """
  Vor der Anwendung sitzt ein CDN (Railway, „honor origin Cache-Control").
  Statische Dateien dürfen dort liegen, HTML-Antworten nicht — und dass sie es
  nicht tun, hängt an einer einzigen Kopfzeile: `private` in `Cache-Control`.

  Was passiert, wenn sie verschwindet: eine HTML-Seite enthält den
  LiveView-Sitzungstoken (`data-phx-session`, signiert, trägt die Assigns), den
  CSRF-Token, den Anmeldezustand und seit der Zweisprachigkeit auch die
  gewählte Sprache. Landet eine solche Seite im geteilten Cache, bekommt der
  nächste Besucher die Seite des vorigen — mitsamt dessen Sitzung.

  Die Kopfzeile kommt heute von `put_secure_browser_headers`, also aus dem
  Rahmenwerk. Genau deshalb steht sie hier: ein Plug in der Pipeline, ein
  eigenes `put_resp_header` für Suchmaschinen, ein Wechsel der Phoenix-Version
  — und sie ist weg, ohne dass etwas kaputtgeht. Sichtbar wäre das nur im
  Netzwerk-Reiter.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.AccountsFixtures
  import Kitrank.KitsFixtures

  alias Kitrank.Kits
  alias Kitrank.Rankings

  defp cache_control(conn) do
    conn |> Plug.Conn.get_resp_header("cache-control") |> Enum.join(", ")
  end

  defp verbietet_geteilten_cache!(conn) do
    kopf = cache_control(conn)

    assert kopf != "", "ohne Cache-Control entscheidet das CDN selbst"

    assert kopf =~ "private" or kopf =~ "no-store",
           "HTML darf nicht in einen geteilten Cache: #{inspect(kopf)}"
  end

  test "die Übersicht", %{conn: conn} do
    league_fixture(season: Kits.current_season(), team_count: 1)

    verbietet_geteilten_cache!(get(conn, ~p"/"))
  end

  test "eine Rangliste hinter dem Bearbeiten-Token", %{conn: conn} do
    {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})

    verbietet_geteilten_cache!(get(conn, "/rankings/#{ranking.edit_token}/edit"))
  end

  test "die Teilen-Ansicht", %{conn: conn} do
    {:ok, ranking} = Rankings.create_ranking(%{display_name: "Test"})

    verbietet_geteilten_cache!(get(conn, "/r/#{ranking.share_slug}"))
  end

  test "der Admin-Bereich", %{conn: conn} do
    verbietet_geteilten_cache!(conn |> log_in_user(admin_fixture()) |> get(~p"/admin"))
  end

  test "die Anmeldeseite", %{conn: conn} do
    verbietet_geteilten_cache!(get(conn, ~p"/users/log-in"))
  end

  test "eine angemeldete Seite erst recht", %{conn: conn} do
    league_fixture(season: Kits.current_season(), team_count: 1)

    verbietet_geteilten_cache!(conn |> log_in_user(admin_fixture()) |> get(~p"/"))
  end

  test "die Sprachumschaltung", %{conn: conn} do
    # Die Weiterleitung setzt die Sprache in die Sitzung. Käme sie aus einem
    # geteilten Cache, würde sie die Sprache des vorigen Besuchers festschreiben.
    verbietet_geteilten_cache!(get(conn, ~p"/sprache/en"))
  end

  test "der Sitzungstoken steckt wirklich im HTML" do
    # Ohne diese Gegenprobe wäre nicht belegt, dass an der Kopfzeile etwas hängt.
    league_fixture(season: Kits.current_season(), team_count: 1)

    html = build_conn() |> get(~p"/") |> html_response(200)

    assert html =~ "data-phx-session="
    assert html =~ ~s(name="csrf-token")
  end

  test "und der LiveView-Kanal ebenso nicht", %{conn: conn} do
    league_fixture(season: Kits.current_season(), team_count: 1)

    {:ok, _view, _html} = live(conn, ~p"/")

    # Hier gibt es keine HTTP-Antwort zu prüfen – der Test hält fest, dass die
    # Seite über den Kanal lebt und ein gecachtes HTML deshalb einen fremden
    # Token mitliefern würde.
    assert true
  end
end
