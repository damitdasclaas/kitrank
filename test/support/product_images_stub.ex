defmodule Kitrank.Kits.ProductImagesStub do
  @moduledoc """
  Ersetzt im Test den echten Shop-Abruf.

  Damit prüfen die Tests den ganzen Weg durch die Oberfläche, ohne dass ein
  fremder Shop erreichbar sein muss — und ohne dass ein Testlauf fremde Server
  belastet.
  """

  @images [
    "https://example.com/a.jpg",
    "https://example.com/b.jpg",
    "https://example.com/c.jpg"
  ]

  def images, do: @images

  # Dieselben Rueckgaben wie das echte Modul – "keine Bilder" ist dort ein
  # Fehler und kein Erfolg mit leerer Liste.
  def fetch("https://stub/leer"), do: {:error, :no_images}
  def fetch("https://stub/js"), do: {:error, :javascript}
  def fetch("https://stub/timeout"), do: {:error, :timeout}
  def fetch("https://stub/blockiert"), do: {:error, :blocked}
  def fetch("kein-link"), do: {:error, :invalid_url}

  # Eine direkte Bildadresse ist ein einzelner Kandidat, keine Seite.
  def fetch("https://stub/bild2.png" = url),
    do:
      {:ok,
       %{kind: :image, title: nil, images: [url], labels: %{}, variants: %{}, source_url: url}}

  def fetch("https://stub/bild.png" = url),
    do:
      {:ok,
       %{kind: :image, title: nil, images: [url], labels: %{}, variants: %{}, source_url: url}}

  def fetch(url) when is_binary(url) do
    {:ok,
     %{
       title: "adidas Heimtrikot 26/27",
       images: @images,
       kind: :page,
       # Manche Shops beschreiben ihre Bilder selbst.
       labels: %{hd(@images) => "Vorderansicht"},
       # Der Shop veroeffentlicht seine kleinen Varianten selbst – so wie es
       # jeder tut, der srcset benutzt. Der Picker nimmt sie mit, ohne dass
       # jemand den Shop kennen muss.
       variants: %{
         hd(@images) => "https://example.com/a.jpg?width=400",
         {:motiv, "/b.jpg"} => "https://example.com/b.jpg?width=400"
       },
       source_url: url
     }}
  end

  def fetch(_), do: {:error, :invalid_url}
end
