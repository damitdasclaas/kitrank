defmodule KitrankWeb.Color do
  @moduledoc """
  Rechnen mit Vereinsfarben.

  Die Übersicht stellt jedes Trikot in der Farbe seines Vereins dar. Damit das
  von Gelb (Dortmund) bis Schwarz (Gladbach) funktioniert, werden Kontrast und
  Abstufungen hier ausgerechnet statt im Template festgelegt.
  """

  # Für Teams ohne hinterlegte Farbe – neutral, aber nicht grau-tot.
  @fallback "#7A847D"
  @ink "#131815"
  @chalk "#F5F7F3"

  @doc "Vereinsfarbe eines Teams, mit Rückfallwert für ungepflegte Stammdaten."
  def team_color(%{primary_color: color}) when is_binary(color), do: color
  def team_color(_), do: @fallback

  @doc """
  Text- bzw. Vordergrundfarbe, die auf `hex` lesbar ist.

  Entscheidet über die relative Leuchtdichte nach WCAG, nicht über einen
  Helligkeits-Daumenwert – sonst kippt genau bei Gelb und Hellblau die falsche
  Richtung heraus.
  """
  def readable_on(hex) do
    if luminance(hex) > 0.42, do: @ink, else: @chalk
  end

  @doc "Relative Leuchtdichte nach WCAG 2, 0.0 (schwarz) bis 1.0 (weiß)."
  def luminance(hex) do
    {r, g, b} = to_rgb(hex)

    0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
  end

  @doc "Mischt `hex` anteilig (0.0–1.0) Richtung `target`."
  def mix(hex, target, amount) do
    {r1, g1, b1} = to_rgb(hex)
    {r2, g2, b2} = to_rgb(target)

    to_hex({
      round(r1 + (r2 - r1) * amount),
      round(g1 + (g2 - g1) * amount),
      round(b1 + (b2 - b1) * amount)
    })
  end

  def darken(hex, amount \\ 0.15), do: mix(hex, "#000000", amount)
  def lighten(hex, amount \\ 0.15), do: mix(hex, "#FFFFFF", amount)

  @doc """
  Variante von `hex`, die sich sichtbar vom Original abhebt – für Ärmel und
  Kragen. Helle Farben werden abgedunkelt, dunkle aufgehellt, damit auch bei
  Schwarz oder Weiß noch eine Kante erkennbar bleibt.
  """
  def contrast_shade(hex, amount \\ 0.22) do
    if luminance(hex) > 0.5, do: darken(hex, amount), else: lighten(hex, amount)
  end

  @doc """
  Variante von `hex`, die auf dunklem Grund lesbar bleibt.

  Ein fester Aufhell-Wert reicht nicht: bei Gladbach-Schwarz käme sonst ein
  Grau heraus, das auf dem abgedunkelten Hintergrund der großen Ansicht
  untergeht. Deshalb wird so weit aufgehellt, bis die Leuchtdichte stimmt.
  """
  def on_dark(hex) do
    Enum.reduce_while([0.0, 0.25, 0.45, 0.65, 0.8], hex, fn amount, _acc ->
      candidate = lighten(hex, amount)
      if luminance(candidate) >= 0.45, do: {:halt, candidate}, else: {:cont, candidate}
    end)
  end

  @doc "Dieselbe Farbe mit Alpha, als `rgb(… / …)` für CSS."
  def alpha(hex, opacity) do
    {r, g, b} = to_rgb(hex)
    "rgb(#{r} #{g} #{b} / #{opacity})"
  end

  defp channel(value) do
    v = value / 255
    if v <= 0.03928, do: v / 12.92, else: :math.pow((v + 0.055) / 1.055, 2.4)
  end

  defp to_rgb("#" <> hex), do: to_rgb(hex)

  defp to_rgb(<<r::binary-2, g::binary-2, b::binary-2>>) do
    {parse(r), parse(g), parse(b)}
  end

  # Kurzform #abc
  defp to_rgb(<<r::binary-1, g::binary-1, b::binary-1>>) do
    {parse(r <> r), parse(g <> g), parse(b <> b)}
  end

  defp to_rgb(_), do: to_rgb(@fallback)

  defp parse(pair) do
    case Integer.parse(pair, 16) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp to_hex({r, g, b}) do
    "#" <>
      ([r, g, b]
       |> Enum.map_join(&(&1 |> clamp() |> Integer.to_string(16) |> String.pad_leading(2, "0")))
       |> String.upcase())
  end

  defp clamp(value), do: value |> max(0) |> min(255)
end
