defmodule KitrankWeb.LegalControllerTest do
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Impressum" do
    test "zeigt Name, Anschrift und Mail", %{conn: conn} do
      conn = get(conn, ~p"/impressum")
      html = html_response(conn, 200)

      assert html =~ "Claas Thore Klein"
      assert html =~ "Stephanhof 8"
      assert html =~ "24943 Flensburg"
      assert html =~ "claasthorek@gmail.com"
      assert html =~ "§ 5 DDG"
    end

    test "englische Fassung ohne deutsche Satzzeichen", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{locale: "en"})
        |> get(~p"/impressum")
        |> html_response(200)

      assert html =~ "Legal notice"
      assert html =~ "Claas Thore Klein"
      refute html =~ "Betreiber"
    end
  end

  describe "Datenschutz" do
    test "nennt Verantwortlichen und was gespeichert wird", %{conn: conn} do
      conn = get(conn, ~p"/datenschutz")
      html = html_response(conn, 200)

      assert html =~ "Datenschutzerklärung"
      assert html =~ "Claas Thore Klein"
      assert html =~ "_kitrank_key"
      assert html =~ "kitrank:rankings"
      assert html =~ "Railway"
    end

    test "englische Fassung", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{locale: "en"})
        |> get(~p"/datenschutz")
        |> html_response(200)

      assert html =~ "Privacy policy"
      assert html =~ "Railway"
      refute html =~ "Verantwortlicher"
    end
  end

  test "die Fußzeile verweist auf beide Seiten", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a[href='/impressum']")
    assert has_element?(view, "a[href='/datenschutz']")
  end
end
