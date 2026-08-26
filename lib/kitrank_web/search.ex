defmodule KitrankWeb.Search do
  @moduledoc """
  Textsuche über Namen, wie Leute sie tippen.

  Kleinschreibung allein reicht bei deutschen Vereinsnamen nicht: wer „koln"
  eingibt, meint Köln, und wer „fussball" eingibt, meint Fußball. Auf einer
  fremden Tastatur ist der Umlaut sonst eine Sackgasse.

  Deshalb werden Akzente über die NFD-Zerlegung abgetrennt und weggeworfen und
  ß zu ss. Das ist keine vollständige Kollation — „ae" findet weiterhin kein
  „ä" —, aber es deckt den Fall ab, der beim Tippen wirklich vorkommt.

  Bewusst im Speicher und nicht in SQL: dafür bräuchte Postgres die
  `unaccent`-Erweiterung, also eine Migration und eine Zusage über die
  Datenbank, die wir für ein paar Dutzend Vereine nicht einlösen wollen.
  """

  @doc "Vergleichsform eines Textes: klein, ohne Akzente, ohne ß."
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace("ß", "ss")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.trim()
  end

  def normalize(nil), do: ""

  @doc """
  Ob einer der Texte die Suche enthält.

  Eine leere Suche trifft alles – so muss kein Aufrufer den Sonderfall selbst
  behandeln.
  """
  def matches?(_texte, query) when query in [nil, ""], do: true

  def matches?(texte, query) when is_list(texte) do
    gesucht = normalize(query)
    gesucht == "" or Enum.any?(texte, &String.contains?(normalize(&1), gesucht))
  end

  def matches?(text, query) when is_binary(text), do: matches?([text], query)
end
