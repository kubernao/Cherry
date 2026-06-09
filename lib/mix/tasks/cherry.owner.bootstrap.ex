defmodule Mix.Tasks.Cherry.Owner.Bootstrap do
  use Mix.Task

  @shortdoc "Creates the first owner account from OWNER_EMAIL and OWNER_PASSWORD"

  @moduledoc """
  Creates the first owner account and prints an initial API token.

      OWNER_EMAIL=you@example.com OWNER_PASSWORD='long-private-password' mix cherry.owner.bootstrap

  The task refuses missing credentials, default credentials, and existing owner accounts.
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Cherry.Release.bootstrap_owner()
  end
end
