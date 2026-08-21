defmodule Kitrank.Kits.Url do
  @moduledoc """
  URL-Validierung für Shop-Links und Bild-URLs.

  Die Werte landen ungefiltert in `href`/`src`, deshalb wird das Schema explizit
  auf http(s) begrenzt – `javascript:` und Konsorten kommen so gar nicht erst in
  die Datenbank.
  """
  import Ecto.Changeset

  def validate_http_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if valid?(value), do: [], else: [{field, "muss mit http:// oder https:// beginnen"}]
    end)
  end

  def validate_http_url_list(changeset, field) do
    validate_change(changeset, field, fn ^field, values ->
      if Enum.all?(values, &valid?/1),
        do: [],
        else: [{field, "alle Bild-URLs müssen mit http:// oder https:// beginnen"}]
    end)
  end

  def valid?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  def valid?(_), do: false
end
