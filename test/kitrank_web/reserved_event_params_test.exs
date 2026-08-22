defmodule KitrankWeb.ReservedEventParamsTest do
  @moduledoc """
  `phx-value-value` ist eine Falle.

  LiveView baut den Event-Payload in zwei Schritten: erst die
  `phx-value-*`-Attribute, danach `meta.value = el.value`. Ein `<button>` hat
  immer ein `value` — bei uns leer. Ein eigener Parameter namens `value` wird
  dadurch überschrieben, und zwar nur im Browser: `render_click` über ein
  Element schickt lediglich die Attribute, der Test bleibt grün.

  Deshalb wird hier im Quelltext geprüft, nicht im Verhalten.
  """
  use ExUnit.Case, async: true

  test "kein Template benutzt phx-value-value" do
    treffer =
      Path.wildcard("lib/**/*.{ex,heex}")
      |> Enum.flat_map(fn pfad ->
        pfad
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {zeile, _} ->
          String.contains?(zeile, "phx-value-value") and not String.contains?(zeile, "#")
        end)
        |> Enum.map(fn {_zeile, nr} -> "#{pfad}:#{nr}" end)
      end)

    assert treffer == [],
           """
           phx-value-value wird von LiveView überschrieben. Nimm einen anderen
           Namen, etwa phx-value-item:

           #{Enum.join(treffer, "\n")}
           """
  end
end
