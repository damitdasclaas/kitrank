defmodule KitrankWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KitrankWeb, :html

  alias Kitrank.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-30 border-b border-line bg-chalk/90 backdrop-blur">
      <div class="mx-auto flex h-14 max-w-[1500px] items-center gap-4 px-4 sm:px-6 lg:px-8">
        <a href={~p"/"} class="kr-display text-lg leading-none">
          Kit<span class="font-normal">Rank</span>
        </a>
        <p class="kr-eyebrow hidden sm:block">Trikots der 1. und 2. Bundesliga</p>
        <div class="ml-auto flex items-center gap-3">
          <%!-- Kein Anmelde-Link: Konten sind noch nicht offen, der Weg hinein
                ist /users/log-in. Wer angemeldet ist, sieht seine Wege. --%>
          <.link
            :if={Scope.admin?(@current_scope)}
            navigate={~p"/admin"}
            class="rounded-md border border-line px-3 py-1.5 text-xs font-medium transition hover:border-ink"
          >
            Admin
          </.link>
          <.link
            :if={@current_scope}
            navigate={~p"/users/settings"}
            class="text-xs text-soft hover:text-ink"
          >
            Konto
          </.link>
          <.link
            :if={@current_scope}
            href={~p"/users/log-out"}
            method="delete"
            class="text-xs text-soft hover:text-ink"
          >
            Abmelden
          </.link>
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <footer class="border-t border-line">
      <div class="mx-auto max-w-[1500px] px-4 py-8 text-xs text-soft sm:px-6 lg:px-8">
        Trikotbilder werden verlinkt, nicht gehostet. Fehlt ein Bild, zeichnet KitRank
        das Trikot in den Vereinsfarben.
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
