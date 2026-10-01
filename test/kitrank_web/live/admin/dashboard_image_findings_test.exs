defmodule KitrankWeb.Admin.DashboardImageFindingsTest do
  @moduledoc """
  Die Bild-Pruefung selbst braucht echtes Netz (siehe Kitrank.Kits.ImageCheck)
  und wird hier nicht ausgeloest. Getestet wird nur, was das Dashboard mit
  bereits gespeicherten Funden tut: anzeigen, umschalten, zur Bearbeitung
  verlinken.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.AccountsFixtures
  import Kitrank.KitsFixtures

  alias Kitrank.Kits.ImageFindings

  setup %{conn: conn} do
    admin = admin_fixture()
    %{conn: log_in_user(conn, admin)}
  end

  test "zeigt gespeicherte Funde, getrennt nach tot und unklar", %{conn: conn} do
    kit = kit_fixture()

    ImageFindings.sync([
      %{
        kit: kit,
        feld: :cutout_url,
        url: "https://shop.example.com/tot.jpg",
        grund: :not_found,
        kategorie: :tot
      },
      %{
        kit: kit,
        feld: :source_shop_url,
        url: "https://shop.example.com/produkt",
        grund: :blocked,
        kategorie: :unklar
      }
    ])

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "wahrscheinlich tot"
    assert html =~ "unklar"
    assert html =~ "tot.jpg"
    assert html =~ "produkt"
    assert html =~ ~p"/admin/trikots/#{kit.id}"
  end

  test "ein Fund laesst sich als erledigt markieren und zuruecksetzen", %{conn: conn} do
    kit = kit_fixture()

    [fund] =
      ImageFindings.sync([
        %{
          kit: kit,
          feld: :cutout_url,
          url: "https://shop.example.com/tot.jpg",
          grund: :not_found,
          kategorie: :tot
        }
      ])

    {:ok, view, _html} = live(conn, ~p"/admin")

    html =
      view
      |> element("button[phx-value-id='#{fund.id}']")
      |> render_click()

    assert html =~ "Zurücksetzen"
    assert ImageFindings.list() |> hd() |> Map.get(:status) == "erledigt"

    html =
      view
      |> element("button[phx-value-id='#{fund.id}']")
      |> render_click()

    assert html =~ "Erledigt"
    refute html =~ "Zurücksetzen"
    assert ImageFindings.list() |> hd() |> Map.get(:status) == "offen"
  end
end
