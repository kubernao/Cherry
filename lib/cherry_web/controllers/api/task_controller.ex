defmodule CherryWeb.Api.TaskController do
  use CherryWeb, :controller

  alias Cherry.Workspace
  import CherryWeb.ApiHelpers

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:project_id, params["project_id"])
      |> Keyword.put(:archived, params["archived"] in ["true", true])

    json(conn, %{tasks: Enum.map(Workspace.list_tasks(opts), &task_json/1)})
  end

  def create(conn, %{"task" => attrs}) do
    case Workspace.create_task(attrs, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, task} -> conn |> put_status(:created) |> json(%{task: task_json(task)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    json(conn, %{task: task_json(Workspace.get_task!(id))})
  end

  def update(conn, %{"id" => id, "task" => attrs}) do
    task = Workspace.get_task!(id)

    case Workspace.update_task(task, attrs, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, task} -> json(conn, %{task: task_json(task)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def move(conn, %{"id" => id, "column_id" => column_id, "position" => position}) do
    task = Workspace.get_task!(id)

    case Workspace.move_task(task, column_id, position,
           actor: "api",
           user_id: conn.assigns.current_user.id
         ) do
      {:ok, task} -> json(conn, %{task: task_json(task)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def done(conn, %{"id" => id}) do
    task = Workspace.get_task!(id)

    case Workspace.complete_task(task, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, task} -> json(conn, %{task: task_json(task)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def archive(conn, %{"id" => id}) do
    task = Workspace.get_task!(id)

    case Workspace.archive_task(task, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, task} -> json(conn, %{task: task_json(task)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def task_json(task) do
    %{
      id: task.id,
      project_id: task.project_id,
      column_id: task.column_id,
      title: task.title,
      body: task.body,
      status: task.status,
      priority: task.priority,
      due_date: task.due_date,
      archived: task.archived,
      position: task.position,
      project: assoc_json(task, :project, [:id, :title, :slug]),
      column: assoc_json(task, :column, [:id, :name]),
      tags:
        Enum.map(
          (Ecto.assoc_loaded?(task.tags) && task.tags) || [],
          &%{id: &1.id, name: &1.name, color: &1.color}
        )
    }
  end

  defp assoc_json(task, assoc, keys) do
    value = Map.get(task, assoc)

    if Ecto.assoc_loaded?(value) && value do
      Map.take(value, keys)
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
