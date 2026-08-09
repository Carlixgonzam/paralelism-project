defmodule WikiRacePlatformWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WikiRacePlatformWeb, :html

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

  attr :active_page, :atom, default: nil, doc: "which nav entry to highlight"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="comic-app-bg min-h-screen pb-16 font-heading text-comic-paper-light">
      <header class="px-4 pt-6 pb-4 sm:px-6 lg:px-8">
        <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-4">
          <a href={~p"/"} class="shrink-0">
            <span class="text-stroke-comic-sm font-display text-3xl tracking-wide text-comic-yellow [text-shadow:3px_3px_0_#000]">
              WIKI RACE
            </span>
          </a>

          <nav class="ml-auto flex flex-wrap items-center gap-3 text-xs font-extrabold tracking-wide sm:text-sm">
            <.nav_link
              navigate={~p"/"}
              active={@active_page == :race}
              rotate="-rotate-[1.5deg]"
              color="bg-comic-red text-comic-paper-light"
            >
              Live Race
            </.nav_link>
            <.nav_link
              navigate={~p"/schedule"}
              active={@active_page == :schedule}
              rotate="rotate-[1deg]"
              color="bg-comic-blue text-comic-paper-light"
            >
              Schedule
            </.nav_link>
            <.nav_link
              navigate={~p"/standings"}
              active={@active_page == :standings}
              rotate="-rotate-[1deg]"
              color="bg-comic-yellow text-black"
            >
              Standings
            </.nav_link>
            <.nav_link
              navigate={~p"/admin"}
              active={@active_page == :admin}
              rotate="rotate-[1.5deg]"
              color="bg-black text-comic-yellow"
            >
              Admin
            </.nav_link>
          </nav>
        </div>
      </header>

      <main class="mx-auto max-w-6xl px-4 pb-8 sm:px-6 lg:px-8">
        <div class="comic-panel p-6 sm:p-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  attr :rotate, :string, default: ""
  attr :color, :string, default: ""
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "inline-block rounded-md border-[3px] border-black px-4 py-2 transition-transform",
        @rotate,
        @color,
        @active && "shadow-comic scale-105",
        !@active && "shadow-comic-pop opacity-85 hover:shadow-comic"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
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
end
