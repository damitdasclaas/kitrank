defmodule Kitrank.Kits.ImageFindingsTest do
  use Kitrank.DataCase, async: true

  import Kitrank.KitsFixtures

  alias Kitrank.Kits.ImageFindings

  defp fund(kit, attrs \\ %{}) do
    Enum.into(attrs, %{
      kit: kit,
      feld: :cutout_url,
      url: "https://shop.example.com/kaputt.jpg",
      grund: :not_found,
      kategorie: :tot
    })
  end

  test "ein neuer Fund wird als offen gespeichert" do
    kit = kit_fixture()

    [gespeichert] = ImageFindings.sync([fund(kit)])

    assert gespeichert.status == "offen"
    assert gespeichert.kategorie == "tot"
    assert gespeichert.kit.id == kit.id
  end

  test "ein erledigter Fund bleibt erledigt, auch wenn er weiter auftritt" do
    kit = kit_fixture()
    [gespeichert] = ImageFindings.sync([fund(kit)])
    ImageFindings.toggle(gespeichert.id)

    # Derselbe Fund kommt beim naechsten Lauf wieder - z.B. weil ein Shop
    # dauerhaft Bot-Abwehr zeigt. Ohne diese Zusicherung waere "erledigt"
    # fuer genau die Faelle nutzlos, fuer die es gedacht ist.
    [nach_zweitem_lauf] = ImageFindings.sync([fund(kit)])

    assert nach_zweitem_lauf.status == "erledigt"
  end

  test "ein Fund, der nicht mehr auftritt, wird geloescht" do
    kit = kit_fixture()
    [_gespeichert] = ImageFindings.sync([fund(kit)])

    assert ImageFindings.sync([]) == []
  end

  test "toggle wechselt zwischen offen und erledigt" do
    kit = kit_fixture()
    [gespeichert] = ImageFindings.sync([fund(kit)])

    erledigt = ImageFindings.toggle(gespeichert.id)
    assert erledigt.status == "erledigt"

    wieder_offen = ImageFindings.toggle(gespeichert.id)
    assert wieder_offen.status == "offen"
  end

  test "list zeigt offene vor erledigten" do
    kit = kit_fixture()

    [a, b] =
      ImageFindings.sync([
        fund(kit, %{feld: :cutout_url, url: "https://shop.example.com/a.jpg"}),
        fund(kit, %{feld: :cutout_url, url: "https://shop.example.com/b.jpg"})
      ])

    ImageFindings.toggle(a.id)

    [erster, zweiter] = ImageFindings.list()
    assert erster.status == "offen"
    assert erster.id == b.id
    assert zweiter.status == "erledigt"
  end
end
