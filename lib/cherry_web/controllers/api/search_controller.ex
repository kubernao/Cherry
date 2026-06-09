defmodule CherryWeb.Api.SearchController do
  use CherryWeb, :controller

  alias Cherry.Workspace

  def index(conn, %{"q" => query}) do
    results = Workspace.search(query)

    json(conn, %{
      projects:
        Enum.map(
          results.projects,
          &%{id: &1.id, title: &1.title, slug: &1.slug, status: &1.status}
        ),
      tasks: Enum.map(results.tasks, &CherryWeb.Api.TaskController.task_json/1)
    })
  end

  def index(conn, _params), do: json(conn, %{projects: [], tasks: []})
end
