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

    aktuelle_schluessel = MapSet.new(auffaellig, &schluessel/1)

    Enum.each(auffaellig, fn eintrag ->
      kit_id = eintrag.kit && eintrag.kit.id
      team_id = eintrag.team && eintrag.team.id

      attrs = %{
        kit_id: kit_id,
        team_id: team_id,
        feld: Atom.to_string(eintrag.feld),
        url: eintrag.url,
        beschreibung: ProductImages.message(eintrag.grund),
        kategorie: Atom.to_string(eintrag.kategorie),
        last_seen_at: jetzt
      }

      case bestehenden_fund(kit_id, team_id, attrs.feld, attrs.url) do
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

  # Repo.get_by lehnt nil als Vergleichswert ab ("unsafe") – kit_id/team_id
  # sind aber hier bewusst oft nil (genau eins von beiden ist gesetzt).
  defp bestehenden_fund(kit_id, team_id, feld, url) do
    kit_filter =
      if kit_id, do: dynamic([f], f.kit_id == ^kit_id), else: dynamic([f], is_nil(f.kit_id))

    team_filter =
      if team_id, do: dynamic([f], f.team_id == ^team_id), else: dynamic([f], is_nil(f.team_id))

    Repo.one(
      from f in ImageFinding,
        where: ^kit_filter,
        where: ^team_filter,
        where: f.feld == ^feld and f.url == ^url
    )
  end

  defp schluessel(eintrag) do
    kit_id = eintrag.kit && eintrag.kit.id
    team_id = eintrag.team && eintrag.team.id
    {kit_id, team_id, Atom.to_string(eintrag.feld), eintrag.url}
  end

  defp loesche_veraltete(aktuelle_schluessel) do
    veraltete_ids =
      from(f in ImageFinding, select: {f.id, f.kit_id, f.team_id, f.feld, f.url})
      |> Repo.all()
      |> Enum.reject(fn {_id, kit_id, team_id, feld, url} ->
        MapSet.member?(aktuelle_schluessel, {kit_id, team_id, feld, url})
      end)
      |> Enum.map(&elem(&1, 0))

    Repo.delete_all(from f in ImageFinding, where: f.id in ^veraltete_ids)
  end

  @doc "Alle gemerkten Funde – offene zuerst, dann die erledigten."
  def list do
    ImageFinding
    |> order_by([f], desc: f.last_seen_at)
    |> Repo.all()
    |> Repo.preload([:team, kit: :team])
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

  @doc """
  Setzt alle Funde einer Kategorie (`"tot"` oder `"unklar"`) auf einmal auf
  `status` – gedacht für die "unklar"-Liste, die bei dauerhafter Bot-Abwehr
  jeden Lauf wieder hundert gleiche Einträge zeigt und die sich niemand
  einzeln anklicken will.
  """
  def mark_all(kategorie, status) when status in ["offen", "erledigt"] do
    jetzt = DateTime.utc_now() |> DateTime.truncate(:second)

    ImageFinding
    |> where([f], f.kategorie == ^kategorie)
    |> Repo.update_all(set: [status: status, updated_at: jetzt])
  end
end
