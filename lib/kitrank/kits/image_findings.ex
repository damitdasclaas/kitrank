defmodule Kitrank.Kits.ImageFindings do
  @moduledoc """
  Persistiert die Funde aus `Kitrank.Kits.ImageCheck`, damit eine Markierung
  als erledigt einen Neustart oder den nächsten Lauf übersteht – dessen
  eigenes Rückgabeformat ist flüchtig und fängt bei jedem Aufruf bei null an.
  """

  import Ecto.Query

  alias Kitrank.Kits.{ImageFinding, ProductImages}
  alias Kitrank.Repo

  @doc """
  Gleicht die gerade gefundenen Probleme mit den gemerkten ab und gibt den
  aktuellen Stand zurück (wie `list/0`).

  Neue Funde kommen als "offen" dazu. Bestehende werden aufgefrischt
  (Beschreibung, Kategorie, Zeitpunkt), ohne ihren Status anzufassen – sonst
  würde "erledigt" bei einem Fund, der wegen Bot-Abwehr jeden Lauf wieder
  auftaucht, seine Bedeutung verlieren. Was nicht mehr auftritt, wird
  gelöscht: die Adresse antwortet wieder, und eine Markierung dafür wäre
  Datenmüll.
  """
  def sync(auffaellig) do
    jetzt = DateTime.utc_now() |> DateTime.truncate(:second)

    aktuelle_schluessel =
      MapSet.new(auffaellig, &{&1.kit.id, Atom.to_string(&1.feld), &1.url})

    Enum.each(auffaellig, fn eintrag ->
      attrs = %{
        kit_id: eintrag.kit.id,
        feld: Atom.to_string(eintrag.feld),
        url: eintrag.url,
        beschreibung: ProductImages.message(eintrag.grund),
        kategorie: Atom.to_string(eintrag.kategorie),
        last_seen_at: jetzt
      }

      case Repo.get_by(ImageFinding, kit_id: attrs.kit_id, feld: attrs.feld, url: attrs.url) do
        nil ->
          %ImageFinding{}
          |> ImageFinding.changeset(Map.put(attrs, :status, "offen"))
          |> Repo.insert!()

        bestehend ->
          bestehend
          |> ImageFinding.changeset(attrs)
          |> Repo.update!()
      end
    end)

    loesche_veraltete(aktuelle_schluessel)

    list()
  end

  defp loesche_veraltete(aktuelle_schluessel) do
    veraltete_ids =
      from(f in ImageFinding, select: {f.id, f.kit_id, f.feld, f.url})
      |> Repo.all()
      |> Enum.reject(fn {_id, kit_id, feld, url} ->
        MapSet.member?(aktuelle_schluessel, {kit_id, feld, url})
      end)
      |> Enum.map(&elem(&1, 0))

    Repo.delete_all(from f in ImageFinding, where: f.id in ^veraltete_ids)
  end

  @doc "Alle gemerkten Funde – offene zuerst, dann die erledigten."
  def list do
    ImageFinding
    |> order_by([f], desc: f.last_seen_at)
    |> Repo.all()
    |> Repo.preload(kit: :team)
    |> Enum.sort_by(&(&1.status == "erledigt"))
  end

  @doc "Status umschalten: offen wird erledigt, erledigt wird wieder offen."
  def toggle(id) do
    finding = Repo.get!(ImageFinding, id)
    neuer_status = if finding.status == "offen", do: "erledigt", else: "offen"

    finding
    |> ImageFinding.changeset(%{status: neuer_status})
    |> Repo.update!()
  end
end
