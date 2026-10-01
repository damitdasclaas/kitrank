defmodule Kitrank.Kits.ImageCheck do
  @moduledoc """
  Prüft, ob die verlinkten Bild- und Shop-Adressen eines Trikots noch
  erreichbar sind.

  Bilder werden nicht gehostet, nur verlinkt (siehe `Kitrank.Kits.Kit`) –
  ändert ein Verein seine Shop-Struktur oder nimmt ein Produkt offline, bricht
  der Link, ohne dass es hier jemand merkt, bis ein Besucher eine leere Kachel
  sieht. Diese Prüfung macht das vorher sichtbar. Nachpflegen bleibt
  Handarbeit im Admin – das hier ersetzt sie nicht, es verkürzt nur die Zeit
  bis jemand merkt, dass es nötig ist.
  """

  import Ecto.Query

  alias Kitrank.Kits.{Kit, ProductImages}
  alias Kitrank.Repo

  # Derselbe User-Agent wie bei ProductImages: ein Shop soll die Anfrage nicht
  # anders behandeln als die eines echten Besuchers.
  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
  @timeout 10_000

  @doc """
  Läuft über alle gespeicherten Bild- und Shop-Adressen und gibt die toten als
  Liste zurück.

  `log` (Standard `IO.puts/1`) bekommt eine Zeile je totem Fund plus eine
  Zusammenfassung – bei hunderten Adressen dauert ein Durchlauf, ohne
  Rückmeldung sähe das nach Hängen aus.
  """
  def run(opts \\ []) do
    sag = Keyword.get(opts, :log, &IO.puts/1)
    nebenlaeufig = Keyword.get(opts, :concurrency, 8)

    pruefungen =
      Repo.all(from k in Kit, preload: [:team])
      |> Enum.flat_map(&adressen/1)

    sag.("#{length(pruefungen)} Adressen werden geprüft …")

    tote =
      pruefungen
      |> Task.async_stream(&pruefe/1,
        max_concurrency: nebenlaeufig,
        timeout: @timeout + 5_000,
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
      |> Enum.flat_map(fn
        {:ok, nil} ->
          []

        {:ok, eintrag} ->
          [eintrag]

        {:exit, {{kit, feld, url}, _grund}} ->
          [%{kit: kit, feld: feld, url: url, grund: :timeout}]
      end)

    Enum.each(tote, &sag.(zeile(&1)))
    sag.("#{length(tote)} von #{length(pruefungen)} Adressen nicht erreichbar")

    tote
  end

  defp adressen(kit) do
    [
      {:cutout_url, kit.cutout_url},
      {:cutout_thumb_url, kit.cutout_thumb_url},
      {:source_shop_url, kit.source_shop_url}
    ]
    |> Kernel.++(Enum.map(kit.model_image_urls || [], &{:model_image_urls, &1}))
    |> Enum.reject(fn {_feld, url} -> is_nil(url) end)
    |> Enum.map(fn {feld, url} -> {kit, feld, url} end)
  end

  defp pruefe({kit, feld, url}) do
    ergebnis =
      case klassifiziere(head(url)) do
        :methode_unerlaubt -> klassifiziere(get_kurz(url))
        sonst -> sonst
      end

    case ergebnis do
      :ok -> nil
      {:fehler, grund} -> %{kit: kit, feld: feld, url: url, grund: grund}
    end
  end

  defp head(url) do
    Req.head(url,
      headers: [{"user-agent", @user_agent}],
      receive_timeout: @timeout,
      max_redirects: 5,
      retry: false
    )
  end

  # Ein Byte reicht als zweiter Versuch, ohne bei hunderten Pruefungen jedesmal
  # ein ganzes Produktbild herunterzuladen.
  defp get_kurz(url) do
    Req.get(url,
      headers: [{"user-agent", @user_agent}, {"range", "bytes=0-0"}],
      receive_timeout: @timeout,
      max_redirects: 5,
      retry: false
    )
  end

  # Dieselben Gruende wie in ProductImages.message/1 – die Texte werden von
  # dort uebernommen, damit es nicht zwei Uebersetzungen fuer denselben Fehler
  # gibt.
  defp klassifiziere({:ok, %{status: status}}) when status in 200..299, do: :ok
  defp klassifiziere({:ok, %{status: 206}}), do: :ok

  defp klassifiziere({:ok, %{status: status}}) when status in [405, 501],
    do: :methode_unerlaubt

  defp klassifiziere({:ok, %{status: 404}}), do: {:fehler, :not_found}

  defp klassifiziere({:ok, %{status: status}}) when status in [401, 403, 429],
    do: {:fehler, :blocked}

  defp klassifiziere({:ok, %{status: status}}), do: {:fehler, {:status, status}}
  defp klassifiziere({:error, %Req.TransportError{reason: :timeout}}), do: {:fehler, :timeout}

  defp klassifiziere({:error, %Req.TransportError{reason: :nxdomain}}),
    do: {:fehler, :unknown_host}

  defp klassifiziere({:error, _exception}), do: {:fehler, :unreachable}

  defp zeile(%{kit: kit, feld: feld, url: url, grund: grund}) do
    "  #{kit.team.short_code} #{bezeichnung(kit)} · #{feld}: #{ProductImages.message(grund)}\n" <>
      "    #{url}"
  end

  defp bezeichnung(%Kit{kit_type: "special", name: name}), do: name || "Sondertrikot"
  defp bezeichnung(%Kit{kit_type: typ}), do: typ
end
