defmodule Kitrank.Repo.Migrations.UrlsOhneLaengengrenze do
  use Ecto.Migration

  def up do
    # Ecto legt :string als varchar(255) an. Fuer URLs ist das zu knapp: die
    # TSG haengt einen base64-kodierten Kontext an ihre Bildadressen, damit
    # kommen 352 Zeichen zusammen. Beim Speichern gab das einen rohen
    # Postgres-Fehler (22001), der die LiveView mitgenommen hat – ohne
    # verstaendliche Meldung fuer den Nutzer.
    #
    # text ist in Postgres nicht langsamer als varchar; die Grenze bringt hier
    # nichts ausser Aerger.
    alter table(:kits) do
      modify :cutout_url, :text
      modify :source_shop_url, :text
      modify :model_image_urls, {:array, :text}
    end

    alter table(:teams) do
      modify :shop_url, :text
    end
  end

  def down do
    alter table(:kits) do
      modify :cutout_url, :string
      modify :source_shop_url, :string
      modify :model_image_urls, {:array, :string}
    end

    alter table(:teams) do
      modify :shop_url, :string
    end
  end
end
