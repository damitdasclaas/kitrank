defmodule KitrankWeb.LocaleController do
  @moduledoc """
  Sprache umschalten.

  Ein normaler Request und kein LiveView-Event, weil die Sitzung nur so
  geschrieben werden kann. Danach zurück, wo man war.
  """
  use KitrankWeb, :controller

  alias KitrankWeb.Locale

  def update(conn, %{"locale" => locale} = params) do
    conn
    |> put_session(:locale, Locale.normalize(locale))
    |> redirect(to: zurueck(params, conn))
  end

  # Nur eigene Pfade, kein offener Redirect nach draussen.
  defp zurueck(%{"return_to" => "/" <> _ = pfad}, _conn), do: pfad
  defp zurueck(_params, _conn), do: "/"
end
