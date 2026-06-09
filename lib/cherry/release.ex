defmodule Cherry.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :cherry

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def bootstrap_owner do
    load_app()

    {:ok, _, _} = Ecto.Migrator.with_repo(Cherry.Repo, fn _repo -> do_bootstrap_owner() end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp do_bootstrap_owner do
    email = required_env!("OWNER_EMAIL")
    password = required_env!("OWNER_PASSWORD")
    validate_owner_credentials!(email, password)

    if Cherry.Accounts.owner_exists?() do
      IO.puts("Owner already exists; no changes made.")
    else
      owner = Cherry.Accounts.ensure_owner!(%{email: email, password: password})

      {:ok, raw, _token} =
        Cherry.Accounts.create_api_token(owner, %{
          name: "Initial CLI token",
          scopes: "read,write,admin"
        })

      IO.puts("""
      Owner created:
        email: #{owner.email}

      Initial API token:
        #{raw}

      Save it for the CLI:
        cherry auth login --url https://cherry.kubernao.org --token #{raw}
      """)
    end
  end

  defp required_env!(name) do
    case System.get_env(name) do
      nil -> raise "#{name} is required"
      "" -> raise "#{name} is required"
      value -> value
    end
  end

  defp validate_owner_credentials!(email, password) do
    cond do
      email == "owner@example.com" ->
        raise "OWNER_EMAIL must not use the default owner@example.com"

      password == "change-me-now!" ->
        raise "OWNER_PASSWORD must not use the default password"

      String.length(password) < 12 ->
        raise "OWNER_PASSWORD must be at least 12 characters"

      true ->
        :ok
    end
  end
end
