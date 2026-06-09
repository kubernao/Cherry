owner =
  Cherry.Accounts.ensure_owner!(%{
    email: System.get_env("OWNER_EMAIL") || "owner@example.com",
    password: System.get_env("OWNER_PASSWORD") || "change-me-now!"
  })

if Cherry.Workspace.list_projects() == [] do
  {:ok, project} =
    Cherry.Workspace.create_project(
      %{
        "title" => "Cherry launch",
        "description" => """
        # Personal workspace

        Use this project to shape Cherry into your own Notion-style operating system.

        - Create tasks from the web UI
        - Move them across kanban columns
        - Use the CLI for agent workflows
        """
      },
      actor: "seed",
      user_id: owner.id
    )

  Cherry.Workspace.create_task(
    %{
      "project_id" => project.id,
      "title" => "Create your first real project",
      "body" => "Replace this seeded project with work you actually care about.",
      "priority" => "normal",
      "tags" => "setup"
    },
    actor: "seed",
    user_id: owner.id
  )
end

case Cherry.Accounts.create_api_token(owner, %{name: "Seed CLI token", scopes: "read,write,admin"}) do
  {:ok, raw, _token} ->
    IO.puts("""

    Owner account:
      email: #{owner.email}
      password: #{System.get_env("OWNER_PASSWORD") || "change-me-now!"}

    Initial API token:
      #{raw}

    Save it for the CLI:
      cherry auth login --url http://localhost:4000 --token #{raw}
    """)

  {:error, _changeset} ->
    :ok
end
