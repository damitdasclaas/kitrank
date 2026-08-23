defmodule KitrankWeb.OriginsTest do
  @moduledoc """
  Der Fall, der die Produktion lahmgelegt hat: PHX_HOST stand auf der alten
  Railway-Domain, die Seite lief unter www.kitrank.pro. Jeder Socket bekam 403,
  LiveView fiel auf Longpoll zurück, wurde auch abgewiesen und versuchte es
  weiter — 89 Versuche, und die Seite blieb leer, ohne Fehlermeldung.

  Deshalb Tests für eine Handvoll Zeilen: der Fehler zeigt sich nicht als
  Ausnahme, sondern als Anfragensturm, und den sieht man erst im Netzwerk-Reiter.
  """
  use ExUnit.Case, async: true

  doctest KitrankWeb.Origins

  alias KitrankWeb.Origins

  describe "allowed/1" do
    test "der Apex erlaubt auch www" do
      assert Origins.allowed("kitrank.pro") == [
               "https://kitrank.pro",
               "https://www.kitrank.pro"
             ]
    end

    test "und www erlaubt auch den Apex" do
      erlaubt = Origins.allowed("www.kitrank.pro")

      assert "https://www.kitrank.pro" in erlaubt
      assert "https://kitrank.pro" in erlaubt
    end

    test "eine Railway-Domain bleibt sie selbst" do
      # Kein Apex zum Ableiten – die Liste darf nichts erfinden, was es nicht
      # gibt, sonst erlaubt sie stillschweigend fremde Hosts.
      assert Origins.allowed("kitrank-production.up.railway.app") == [
               "https://kitrank-production.up.railway.app",
               "https://www.kitrank-production.up.railway.app"
             ]
    end

    test "nur https – hinter dem Proxy gibt es nichts anderes" do
      refute Enum.any?(Origins.allowed("kitrank.pro"), &String.starts_with?(&1, "http://"))
    end

    test "Leerzeichen aus der Variable stören nicht" do
      assert Origins.allowed("  kitrank.pro  ") == Origins.allowed("kitrank.pro")
    end

    test "keine Dubletten" do
      liste = Origins.allowed("kitrank.pro")
      assert liste == Enum.uniq(liste)
    end
  end

  describe "configured/2" do
    test "ohne Variable wird abgeleitet" do
      assert Origins.configured("kitrank.pro", nil) == Origins.allowed("kitrank.pro")
      assert Origins.configured("kitrank.pro", "") == Origins.allowed("kitrank.pro")
    end

    test "eine eigene Liste schlägt die Ableitung" do
      assert Origins.configured("kitrank.pro", "https://a.example, https://b.example") ==
               ["https://a.example", "https://b.example"]
    end

    test "eine Liste aus Kommas und Leerzeichen fällt auf die Ableitung zurück" do
      # Sonst wäre check_origin eine leere Liste – und die lehnt *alles* ab,
      # also genau der Ausfall, den dieses Modul verhindern soll.
      assert Origins.configured("kitrank.pro", " , ,") == Origins.allowed("kitrank.pro")
    end

    test "\"false\" schaltet die Prüfung ab" do
      assert Origins.configured("kitrank.pro", "false") == false
    end

    test "gibt niemals eine leere Liste zurück" do
      for wert <- [nil, "", " ", ",", " , , "] do
        assert Origins.configured("kitrank.pro", wert) != []
      end
    end
  end

  test "die Produktionskonfiguration ruft das hier auf" do
    # Ein Test des Moduls sagt nichts, wenn runtime.exs es nicht benutzt – und
    # runtime.exs selbst läuft in keinem Test.
    quelle = File.read!("config/runtime.exs")

    assert quelle =~ "check_origin: KitrankWeb.Origins.configured(host,"
    assert quelle =~ "PHX_CHECK_ORIGIN"
  end
end
