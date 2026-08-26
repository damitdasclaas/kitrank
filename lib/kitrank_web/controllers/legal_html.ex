defmodule KitrankWeb.LegalHTML do
  @moduledoc """
  Templates für Impressum und Datenschutzerklärung.

  Der laufende Text steht zweisprachig in den Templates, nicht in Gettext:
  Rechtstexte sollen nicht über `.po`-Dateien wandern, und die deutsche Fassung
  bleibt die rechtlich maßgebliche.
  """
  use KitrankWeb, :html

  embed_templates "legal_html/*"

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article class="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <p class="kr-eyebrow">{@eyebrow}</p>
        <h1 class="kr-display mt-2 text-4xl leading-[0.95]">{@title}</h1>
        <div class="mt-10 space-y-8 text-sm leading-relaxed">
          {render_slot(@inner_block)}
        </div>
      </article>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section class="space-y-3">
      <h2 class="font-semibold text-ink">{@title}</h2>
      <div class="space-y-3 text-soft">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
