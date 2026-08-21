defmodule KitrankWeb.KitComponents do
  @moduledoc """
  Bausteine für die Trikot-Darstellung.

  Solange für ein Trikot kein Bild hinterlegt ist – und das ist der Normalfall,
  weil Bilder verlinkt und nicht gehostet werden –, zeichnet `kit_figure/1` das
  Trikot als SVG in den Vereinsfarben. Der Kit-Typ bestimmt dabei das Muster, so
  dass Heim, Auswärts, Ausweich und Sonder auch ohne Foto unterscheidbar sind.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import KitrankWeb.CoreComponents, only: [icon: 1]

  alias Kitrank.Kits.Kit
  alias KitrankWeb.Color

  # Trikot-Silhouette auf 100x110: Kragen, Schultern, Ärmel, leicht taillierter
  # Rumpf. Ein Pfad für die Gesamtform, ein zweiter Satz für die Ärmel, damit
  # sich beide getrennt einfärben lassen.
  @body_path "M40,6 C34,6 30,7 26,10 L6,28 L15,45 L29,33 L29,104 L71,104 L71,33 L85,45 L94,28 L74,10 C70,7 66,6 60,6 C57,14 43,14 40,6 Z"
  @left_sleeve "M26,10 L6,28 L15,45 L29,33 L29,16 Z"
  @right_sleeve "M74,10 L94,28 L85,45 L71,33 L71,16 Z"
  @collar "M40,6 C43,14 57,14 60,6"

  attr :kit, :map, required: true, doc: "das Trikot"
  attr :team, :map, required: true, doc: "das Team, für die Vereinsfarbe"
  attr :class, :string, default: nil
  attr :image_url, :string, default: nil, doc: "überschreibt die Auswahl des Bildes"

  @doc """
  Ein Trikot als Bild, falls hinterlegt – sonst als gezeichnete Silhouette.
  """
  def kit_figure(assigns) do
    assigns =
      assigns
      |> assign_new(:src, fn -> assigns.image_url || assigns.kit.cutout_url end)
      |> assign(:color, Color.team_color(assigns.team))

    ~H"""
    <div class={["relative flex items-center justify-center", @class]}>
      <img
        :if={@src}
        src={@src}
        alt={"#{@team.name} – #{Kit.label(@kit.kit_type)}"}
        loading="lazy"
        class="h-full w-full object-contain"
      />
      <.kit_silhouette :if={!@src} kit={@kit} color={@color} />
    </div>
    """
  end

  attr :kit, :map, required: true
  attr :color, :string, required: true

  @doc """
  Die gezeichnete Trikot-Silhouette. Kein Foto-Ersatz, sondern eine ehrliche
  Darstellung dessen, was bekannt ist: Verein, Farbe, Kit-Typ.
  """
  def kit_silhouette(assigns) do
    assigns =
      assigns
      |> assign(:palette, palette(assigns.kit.kit_type, assigns.color))
      |> assign(:paths, %{
        body: @body_path,
        left: @left_sleeve,
        right: @right_sleeve,
        collar: @collar
      })
      |> assign(:uid, "kit-#{assigns.kit.id}-#{System.unique_integer([:positive])}")

    ~H"""
    <svg
      viewBox="0 0 100 110"
      class="h-full w-full"
      role="img"
      aria-label={"#{Kit.label(@kit.kit_type)} (Platzhalter, kein Foto hinterlegt)"}
    >
      <defs :if={@palette.band}>
        <clipPath id={@uid}>
          <path d={@paths.body} />
        </clipPath>
      </defs>

      <path d={@paths.body} fill={@palette.body} />

      <g :if={@palette.band} clip-path={"url(##{@uid})"}>
        <path d={@palette.band.d} fill={@palette.band.fill} />
      </g>

      <path d={@paths.left} fill={@palette.sleeve} />
      <path d={@paths.right} fill={@palette.sleeve} />

      <path
        d={@paths.collar}
        fill="none"
        stroke={@palette.trim}
        stroke-width="5"
        stroke-linecap="round"
      />
      <path
        d={@paths.body}
        fill="none"
        stroke={@palette.outline}
        stroke-width="1.5"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  # Jeder Kit-Typ bekommt ein eigenes Muster, damit vier Trikots desselben
  # Vereins nebeneinander nicht viermal gleich aussehen.
  defp palette("home", color) do
    %{
      body: color,
      sleeve: Color.contrast_shade(color, 0.18),
      trim: Color.readable_on(color),
      outline: Color.alpha(Color.readable_on(color), 0.25),
      band: nil
    }
  end

  defp palette("away", color) do
    %{
      body: "#F4F6F2",
      sleeve: color,
      trim: color,
      outline: "rgb(0 0 0 / 0.16)",
      band: nil
    }
  end

  defp palette("third", color) do
    %{
      body: "#1B211D",
      sleeve: Color.darken(color, 0.25),
      trim: Color.lighten(color, 0.25),
      outline: "rgb(255 255 255 / 0.18)",
      # Brustband quer über den Rumpf, an der Silhouette abgeschnitten.
      band: %{d: "M0,44 L100,30 L100,50 L0,64 Z", fill: color}
    }
  end

  defp palette("special", color) do
    %{
      body: color,
      sleeve: Color.contrast_shade(color, 0.3),
      trim: Color.readable_on(color),
      outline: Color.alpha(Color.readable_on(color), 0.25),
      # Diagonale, wie sie Sondertrikots gern haben.
      band: %{
        d: "M-10,110 L60,-10 L86,-10 L16,110 Z",
        fill: Color.alpha(Color.readable_on(color), 0.16)
      }
    }
  end

  defp palette(_other, color), do: palette("home", color)

  attr :kit_type, :string, required: true
  attr :class, :string, default: nil

  @doc "Kurzmarke für den Kit-Typ – H, A, 3 oder S."
  def kit_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex h-5 w-5 items-center justify-center rounded-[3px] font-mono text-[10px]",
        "font-semibold leading-none tracking-tight",
        @class
      ]}
      title={Kit.label(@kit_type)}
    >
      {short_badge(@kit_type)}
    </span>
    """
  end

  @doc """
  Alle Bilder eines Trikots in Anzeige-Reihenfolge: Cutout zuerst, dann die
  Model-Bilder. Leer, wenn nichts hinterlegt ist – dann zeichnet
  `kit_figure/1` die Silhouette.
  """
  def kit_images(%{cutout_url: cutout, model_image_urls: models}) do
    Enum.reject([cutout | models || []], &is_nil/1)
  end

  def kit_images(_), do: []

  attr :id, :string, required: true
  attr :close_path, :string, required: true, doc: "Ziel beim Schliessen"
  attr :label, :string, required: true, doc: "Beschriftung fuer Screenreader"
  attr :size, :string, default: "max-w-3xl"
  slot :inner_block, required: true

  @doc "Modal-Huelle: Backdrop, Escape zum Schliessen, Fokus auf dem Dialog."
  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-label={@label}
      phx-window-keydown={JS.patch(@close_path)}
      phx-key="Escape"
    >
      <div
        class="fixed inset-0 bg-black/45 backdrop-blur-[2px]"
        aria-hidden="true"
        phx-click={JS.patch(@close_path)}
      >
      </div>

      <div class="relative flex min-h-full items-start justify-center p-3 sm:p-6">
        <div class={[
          "kr-rise relative w-full rounded-xl border border-line bg-panel shadow-2xl",
          @size
        ]}>
          <.link
            patch={@close_path}
            class="absolute right-3 top-3 z-10 flex h-8 w-8 items-center justify-center rounded-full border border-line bg-panel text-soft transition hover:text-ink"
            aria-label="Schliessen"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </.link>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp short_badge("home"), do: "H"
  defp short_badge("away"), do: "A"
  defp short_badge("third"), do: "3"
  defp short_badge("special"), do: "S"
  defp short_badge(other), do: String.first(other) |> String.upcase()
end
