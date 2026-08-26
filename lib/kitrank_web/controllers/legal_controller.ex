defmodule KitrankWeb.LegalController do
  @moduledoc """
  Impressum und Datenschutzerklärung.

  Statische Seiten, kein LiveView: der Inhalt ändert sich nicht pro Request,
  und ein Socket wäre nur Apparat. Der Browser-Pipeline reicht – Locale,
  `current_scope` und Flash kommen von dort.
  """
  use KitrankWeb, :controller

  plug :put_layout, false

  @betreiber %{
    name: "Claas Thore Klein",
    street: "Stephanhof 8",
    city: "24943 Flensburg",
    email: "claasthorek@gmail.com"
  }

  def impressum(conn, _params) do
    conn
    |> assign(:page_title, gettext("Impressum"))
    |> assign(:betreiber, @betreiber)
    |> assign(:locale, Gettext.get_locale(KitrankWeb.Gettext))
    |> render(:impressum)
  end

  def datenschutz(conn, _params) do
    conn
    |> assign(:page_title, gettext("Datenschutz"))
    |> assign(:betreiber, @betreiber)
    |> assign(:locale, Gettext.get_locale(KitrankWeb.Gettext))
    |> render(:datenschutz)
  end
end
