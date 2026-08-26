defmodule KitrankWeb.LocaleTest do
  @moduledoc """
  Sprachwahl.

  Zwei Stellen brechen in LiveView-Anwendungen regelmäßig, und genau die
  prüfen die Tests hier: der erste, statische Aufruf läuft im Request-Prozess,
  jedes weitere Rendern im LiveView-Prozess — wer nur den Plug einhängt,
  bekommt eine Seite, die nach dem Verbinden in die Quellsprache zurückfällt.
  """
  use KitrankWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kitrank.KitsFixtures

  alias Kitrank.Kits

  setup do
    league_fixture(season: Kits.current_season(), team_count: 1)
    :ok
  end

  describe "Umschalter" do
    test "merkt die Wahl in der Sitzung", %{conn: conn} do
      conn = get(conn, ~p"/sprache/en")

      assert redirected_to(conn) == "/"
      assert get_session(conn, :locale) == "en"
    end

    test "nimmt nur unterstützte Sprachen", %{conn: conn} do
      conn = get(conn, ~p"/sprache/kl")

      assert get_session(conn, :locale) == "de"
    end

    test "kehrt dorthin zurück, wo man war", %{conn: conn} do
      conn = get(conn, "/sprache/en?return_to=%2Frankings%2Fnew")

      assert redirected_to(conn) == "/rankings/new"
    end

    test "folgt keinem Ziel auf einem anderen Host", %{conn: conn} do
      # Sonst wäre der Umschalter eine offene Weiterleitung: ein Link
      # /sprache/de?return_to=https://... würde von der eigenen Seite
      # wegführen und sähe dabei vertrauenswürdig aus.
      conn = get(conn, "/sprache/en?return_to=https%3A%2F%2Ffremd.example%2Fx")

      assert redirected_to(conn) == "/"
    end
  end

  describe "Erkennung" do
    test "Deutsch ist die Voreinstellung", %{conn: conn} do
      assert html_response(get(conn, ~p"/"), 200) =~ "Welches Trikot ist das schönste?"
    end

    test "richtet sich nach dem Browser, solange nichts gewählt wurde", %{conn: conn} do
      html =
        conn
        |> put_req_header("accept-language", "en-GB,en;q=0.9")
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Which kit is the best looking?"
    end

    test "die eigene Wahl schlägt den Browser", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{locale: "de"})
        |> put_req_header("accept-language", "en-GB,en;q=0.9")
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Welches Trikot ist das schönste?"
    end
  end

  describe "im LiveView-Prozess" do
    test "die Sprache hält über das Verbinden hinaus", %{conn: conn} do
      # Der Kern der Sache: live/2 rendert zweimal – einmal statisch im
      # Request, dann verbunden im LiveView-Prozess. Ohne on_mount-Hook
      # stimmt nur der erste Durchgang.
      conn = init_test_session(conn, %{locale: "en"})

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Which kit is the best looking?"
      assert render(view) =~ "Which kit is the best looking?"
      refute render(view) =~ "Welches Trikot ist das schönste?"
    end

    test "auch nach einem Ereignis", %{conn: conn} do
      # Gettext.put_locale/1 gilt pro Prozess. Ein handle_event läuft im
      # selben LiveView-Prozess, darf die Sprache also nicht verlieren –
      # ein Test, der nur mount prüft, würde das nicht merken.
      conn = init_test_session(conn, %{locale: "en"})
      {:ok, view, _html} = live(conn, ~p"/")
      # Ligen starten zugeklappt; ohne Kachel gibt es keinen Knopf zum Klicken.
      view |> element(~s{button[phx-click="toggle_league"]}) |> render_click()

      html = view |> element(~s{button[data-role="tile-compare"]}) |> render_click()

      assert html =~ "Compare"
      refute html =~ "Vergleich"
    end

    test "Trikot-Bezeichnungen übersetzen mit", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "en"})

      {:ok, _view, html} = live(conn, ~p"/")

      # "Heim" steckt nicht in der Vorlage, sondern kommt aus KitLabel –
      # eine Bezeichnung aus einem Modul ist genau die Sorte Text, die beim
      # Übersetzen liegen bleibt.
      assert html =~ "Home"
      refute html =~ ">Heim<"
    end
  end

  describe "Katalog" do
    test "jede deutsche Meldung hat eine englische Entsprechung" do
      # Ein leeres msgstr fällt auf die msgid zurück – die Seite wäre dann
      # halb englisch, halb deutsch, ohne dass etwas kaputtgeht.
      po = File.read!("priv/gettext/en/LC_MESSAGES/default.po")

      leer =
        po
        |> String.split(~r/\n\n+/)
        |> Enum.filter(&(&1 =~ ~r/^msgid "(?!")/m and &1 =~ ~r/^msgstr ""$/m))
        |> Enum.map(&(Regex.run(~r/^msgid "(.*)"/m, &1) |> List.last()))

      assert leer == []
    end

    test "keine Meldung ist als vorläufig markiert" do
      # fuzzy heisst: von gettext geraten, nicht gelesen.
      refute File.read!("priv/gettext/en/LC_MESSAGES/default.po") =~ "#, fuzzy"
    end

    test "der deutsche Katalog bleibt leer" do
      # Deutsch ist die Quellsprache: die msgid *ist* der deutsche Text. Ein
      # gefülltes de/default.po wäre eine zweite Quelle für denselben Text und
      # würde den Quelltext still überschreiben. Wer die deutsche Fassung
      # ändern will, ändert die msgid.
      pfad = "priv/gettext/de/LC_MESSAGES/default.po"

      gefuellt =
        if File.exists?(pfad) do
          pfad
          |> File.read!()
          |> then(&Regex.scan(~r/^msgstr "(.+)"$/m, &1))
          |> Enum.map(&List.last/1)
        else
          []
        end

      assert gefuellt == []
    end

    test "Ecto-Fehlermeldungen liegen auf Deutsch vor" do
      # Sie kommen englisch aus Ecto. Fuer die eigenen Texte ist Deutsch die
      # Quellsprache, fuer diese nicht – deshalb braucht "errors" auch einen
      # de-Katalog.
      assert Gettext.with_locale(KitrankWeb.Gettext, "de", fn ->
               Gettext.dgettext(KitrankWeb.Gettext, "errors", "can't be blank")
             end) == "darf nicht leer sein"
    end
  end
end
