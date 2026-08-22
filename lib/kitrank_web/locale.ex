defmodule KitrankWeb.Locale do
  @moduledoc """
  Sprache bestimmen und setzen — für normale Requests und für LiveViews.

  Reihenfolge: was in der Sitzung steht, sonst was der Browser über
  `Accept-Language` mitbringt, sonst Deutsch.

  Bewusst über die Sitzung und nicht über ein URL-Präfix. Ein Präfix wäre für
  Suchmaschinen besser, würde aber jede Route umbauen — das ist eine eigene
  Entscheidung und kein Nebeneffekt der Übersetzung.

  Der LiveView-Prozess ist ein anderer als der des Requests, deshalb muss die
  Sprache dort noch einmal gesetzt werden. Genau daran scheitert Übersetzung in
  LiveView-Anwendungen meistens.
  """

  @behaviour Plug

  @supported ~w(de en)
  @default "de"

  def supported, do: @supported
  def default, do: @default

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = from_session_or_header(conn)
    Gettext.put_locale(KitrankWeb.Gettext, locale)

    Plug.Conn.put_session(conn, :locale, locale)
  end

  @doc """
  `on_mount`-Hook: setzt die Sprache im LiveView-Prozess.

  Ohne das rendert die erste (statische) Antwort übersetzt und alles danach
  wieder auf Deutsch.
  """
  def on_mount(:default, _params, session, socket) do
    Gettext.put_locale(KitrankWeb.Gettext, normalize(session["locale"]))

    {:cont, socket}
  end

  @doc "Ist das eine Sprache, die wir haben?"
  def supported?(locale), do: locale in @supported

  @doc "Bringt beliebige Eingaben auf eine unterstützte Sprache."
  def normalize(locale) when is_binary(locale) do
    if supported?(locale), do: locale, else: @default
  end

  def normalize(_), do: @default

  defp from_session_or_header(conn) do
    cond do
      locale = Plug.Conn.get_session(conn, :locale) -> normalize(locale)
      locale = from_header(conn) -> locale
      true -> @default
    end
  end

  # "de-DE,de;q=0.9,en;q=0.8" -> "de". Nur der Sprachteil zaehlt, Regionen
  # unterscheiden wir nicht.
  defp from_header(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-language")
    |> List.first()
    |> to_string()
    |> String.split(",")
    |> Enum.map(fn teil ->
      teil |> String.split(";") |> hd() |> String.trim() |> String.split("-") |> hd()
    end)
    |> Enum.find(&supported?/1)
  end
end
