defmodule CherryWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CherryWeb, :html

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
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the signed-in user"
  attr :wide, :boolean, default: false, doc: "whether content should use the full viewport width"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-[radial-gradient(circle_at_top_left,#fff7ed_0,#f7efe3_34rem,#f8f5ef_100%)] text-stone-950 dark:bg-[radial-gradient(circle_at_top_left,#3b171a_0,#1c1917_28rem,#0c0a09_100%)] dark:text-stone-50">
      <header class="pointer-events-none fixed right-4 top-4 z-40 sm:right-6 lg:right-8">
        <div class="pointer-events-auto flex items-center gap-3 rounded-2xl border border-stone-200/80 bg-white/80 p-2 shadow-lg shadow-stone-900/10 backdrop-blur-xl dark:border-stone-800/80 dark:bg-stone-950/80 dark:shadow-black/30">
          <span
            :if={@current_user}
            class="hidden max-w-48 truncate text-sm text-stone-500 md:block dark:text-stone-400"
          >
            {@current_user.email}
          </span>
          <.theme_toggle />
          <.link
            :if={@current_user}
            href={~p"/logout"}
            method="delete"
            id="app-sign-out"
            class="rounded-lg border border-stone-200 bg-white px-3 py-2 text-sm font-medium text-stone-700 shadow-sm transition hover:-translate-y-0.5 hover:border-stone-300 hover:bg-stone-50 hover:text-stone-950 dark:border-stone-700 dark:bg-stone-900 dark:text-stone-200 dark:hover:border-stone-600 dark:hover:bg-stone-800 dark:hover:text-stone-50"
          >
            Sign out
          </.link>
          <.link
            :if={!@current_user}
            navigate={~p"/login"}
            id="app-sign-in"
            class="rounded-lg bg-stone-950 px-3 py-2 text-sm font-medium text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
          >
            Sign in
          </.link>
        </div>
      </header>

      <div class={[
        "mx-auto px-4 py-6 pt-24 sm:px-6 lg:px-8",
        @wide && "max-w-none",
        !@wide && "max-w-7xl"
      ]}>
        {render_slot(@inner_block)}
      </div>

      <.flash_group flash={@flash} />
    </div>
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
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
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
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
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
    <div
      id="theme-toggle"
      class="relative flex items-center rounded-lg border border-stone-200 bg-stone-100 p-0.5 shadow-inner dark:border-stone-700 dark:bg-stone-800"
    >
      <div class="absolute left-0.5 top-0.5 h-8 w-8 rounded-md border border-stone-200 bg-white shadow-sm transition-[left] dark:border-stone-600 dark:bg-stone-950 [[data-theme=light]_&]:left-[2.125rem] [[data-theme=dark]_&]:left-[4.125rem]" />

      <button
        class="relative grid size-8 cursor-pointer place-items-center rounded-md text-stone-500 transition hover:text-stone-950 dark:text-stone-400 dark:hover:text-stone-50"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative grid size-8 cursor-pointer place-items-center rounded-md text-stone-500 transition hover:text-stone-950 dark:text-stone-400 dark:hover:text-stone-50"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative grid size-8 cursor-pointer place-items-center rounded-md text-stone-500 transition hover:text-stone-950 dark:text-stone-400 dark:hover:text-stone-50"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
