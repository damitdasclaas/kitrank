defmodule Kitrank.Kits.Season do
  @moduledoc """
  Saison-Bezeichner im Format "2026/27".

  Bewusst ein String statt zweier Integer: er wird überall direkt angezeigt und
  sortiert als String korrekt, solange das Format einheitlich ist – dafür sorgt
  `validate/2`.
  """
  import Ecto.Changeset

  @format ~r"^\d{4}/\d{2}$"

  @doc "Erzwingt das Format \"2026/27\" inklusive plausibler Jahresfolge."
  def validate(changeset, field) do
    changeset
    |> validate_format(field, @format, message: ~s(Format "2026/27"))
    |> validate_change(field, fn ^field, value ->
      case parse(value) do
        {:ok, _} -> []
        :error -> [{field, "Endjahr muss auf das Startjahr folgen"}]
      end
    end)
  end

  @doc """
  Zerlegt "2026/27" in `{:ok, {2026, 2027}}`.

  Gibt `:error` zurück, wenn das Format nicht passt oder das Endjahr nicht direkt
  auf das Startjahr folgt.
  """
  def parse(value) when is_binary(value) do
    with true <- Regex.match?(@format, value),
         [start_year, short_end] <- String.split(value, "/"),
         {start_year, ""} <- Integer.parse(start_year),
         {short_end, ""} <- Integer.parse(short_end),
         end_year = div(start_year, 100) * 100 + short_end,
         end_year = if(end_year < start_year, do: end_year + 100, else: end_year),
         true <- end_year == start_year + 1 do
      {:ok, {start_year, end_year}}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc ~s(Baut den Saison-String für ein Startjahr: `2026` -> `"2026/27"`.)
  def from_start_year(start_year) when is_integer(start_year) do
    "#{start_year}/#{String.pad_leading(to_string(rem(start_year + 1, 100)), 2, "0")}"
  end

  @doc """
  Die Saison, in der ein Datum liegt – Stichtag 1. Juli.

  Damit zeigt die Übersicht ab Sommer automatisch die neue Saison, ohne dass
  irgendwo ein Default nachgezogen werden muss.
  """
  def current(today \\ Date.utc_today()) do
    if today.month >= 7, do: from_start_year(today.year), else: from_start_year(today.year - 1)
  end
end
