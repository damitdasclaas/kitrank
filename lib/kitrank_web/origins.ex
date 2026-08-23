defmodule KitrankWeb.Origins do
  @moduledoc """
  Welche Herkunft darf einen Socket öffnen.

  Warum es das gibt: `check_origin` prüft standardmäßig gegen `url: [host: ...]`,
  also gegen `PHX_HOST` — und zwar genau. Läuft die Seite unter `www.beispiel.de`,
  während `PHX_HOST` auf `beispiel.de` steht, weist der Endpunkt den Socket mit
  403 ab. LiveView fällt dann auf Longpoll zurück, das ebenfalls abgewiesen wird,
  und versucht es weiter: `_mount_attempts=89`. Aus einem fehlenden `www.` wird
  ein Anfragensturm, und die Seite bleibt leer, ohne eine Fehlermeldung zu zeigen.

  Deshalb gilt hier beides als dieselbe Seite. Für alles andere (eigene
  Zweitdomain, Vorschau-Umgebung) gibt es `PHX_CHECK_ORIGIN` als
  kommagetrennte Liste.
  """

  @doc """
  Erlaubte Herkünfte für einen Host.

  Gibt `PHX_HOST` und die jeweils andere `www`-Schreibweise zurück — beides mit
  `https`, weil die Anwendung hinter dem Railway-Proxy nur so erreichbar ist.

      iex> KitrankWeb.Origins.allowed("kitrank.pro")
      ["https://kitrank.pro", "https://www.kitrank.pro"]

      iex> KitrankWeb.Origins.allowed("www.kitrank.pro")
      ["https://www.kitrank.pro", "https://kitrank.pro"]
  """
  def allowed(host) when is_binary(host) do
    host = String.trim(host)
    ohne = String.replace_prefix(host, "www.", "")
    mit = "www." <> ohne

    ["https://" <> host, "https://" <> ohne, "https://" <> mit]
    |> Enum.uniq()
  end

  @doc """
  Wie `allowed/1`, aber `PHX_CHECK_ORIGIN` schlägt alles.

  Leer oder nicht gesetzt heißt: aus dem Host ableiten. `"false"` schaltet die
  Prüfung ab — nur für die lokale Entwicklung gedacht, nie in Produktion, weil
  dann jede fremde Seite einen Socket öffnen darf.
  """
  def configured(host, nil), do: allowed(host)
  def configured(host, ""), do: allowed(host)
  def configured(_host, "false"), do: false

  def configured(host, liste) when is_binary(liste) do
    case liste |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] -> allowed(host)
      eigene -> eigene
    end
  end
end
