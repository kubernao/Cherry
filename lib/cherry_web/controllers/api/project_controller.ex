defmodule CherryWeb.Api.ProjectController do
  use CherryWeb, :controller

  alias Cherry.Workspace
  import CherryWeb.ApiHelpers

  def index(conn, params) do
    archived = params["archived"] in ["true", true]

    json(conn, %{projects: Enum.map(Workspace.list_projects(archived: archived), &project_json/1)})
  end

  def create(conn, %{"project" => attrs}) do
    case Workspace.create_project(attrs, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, project} -> conn |> put_status(:created) |> json(%{project: project_json(project)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    project = Workspace.get_project!(id)
    json(conn, %{project: project_json(project, true)})
  end

  def update(conn, %{"id" => id, "project" => attrs}) do
    project = Workspace.get_project!(id)

    case Workspace.update_project(project, attrs,
           actor: "api",
           user_id: conn.assigns.current_user.id
         ) do
      {:ok, project} -> json(conn, %{project: project_json(project)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def archive(conn, %{"id" => id}) do
    project = Workspace.get_project!(id)

    case Workspace.archive_project(project, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, project} -> json(conn, %{project: project_json(project)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def restore(conn, %{"id" => id}) do
    project = Workspace.get_project!(id)

    case Workspace.restore_project(project, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, project} -> json(conn, %{project: project_json(project)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    project = Workspace.get_project!(id)

    case Workspace.delete_project(project, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, _project} -> send_resp(conn, :no_content, "")
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  defp project_json(project, expanded \\ false) do
    base = %{
      id: project.id,
      title: project.title,
      slug: project.slug,
      description: project.description,
      status: project.status,
      priority: project.priority,
      archived: project.archived
    }

    if expanded do
      Map.merge(base, %{
        columns: Enum.map(project.columns, &%{id: &1.id, name: &1.name, position: &1.position}),
        tasks: Enum.map(project.tasks, &CherryWeb.Api.TaskController.task_json/1)
      })
    else
      base
    end
  end
end
