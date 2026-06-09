defmodule CherryWeb.Api.ColumnController do
  use CherryWeb, :controller

  alias Cherry.Workspace
  import CherryWeb.ApiHelpers

  def index(conn, %{"project_id" => project_id}) do
    project = Workspace.get_project!(project_id)
    json(conn, %{columns: Enum.map(Workspace.list_columns(project.id), &column_json/1)})
  end

  def create(conn, %{"column" => attrs}) do
    project = Workspace.get_project!(attrs["project_id"])

    case Workspace.create_column(project, attrs,
           actor: "api",
           user_id: conn.assigns.current_user.id
         ) do
      {:ok, column} -> conn |> put_status(:created) |> json(%{column: column_json(column)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id, "column" => attrs}) do
    column = Workspace.get_column!(id)

    case Workspace.update_column(column, attrs,
           actor: "api",
           user_id: conn.assigns.current_user.id
         ) do
      {:ok, column} -> json(conn, %{column: column_json(column)})
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def move(conn, %{"id" => id, "position" => position}) do
    column = Workspace.get_column!(id)

    case Workspace.move_column(column, position,
           actor: "api",
           user_id: conn.assigns.current_user.id
         ) do
      {:ok, column} -> json(conn, %{column: column_json(column)})
      {:error, reason} -> render_operation_error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    column = Workspace.get_column!(id)

    case Workspace.delete_column(column, actor: "api", user_id: conn.assigns.current_user.id) do
      {:ok, _column} -> send_resp(conn, :no_content, "")
      {:error, reason} -> render_operation_error(conn, reason)
    end
  end

  defp column_json(column) do
    %{
      id: column.id,
      project_id: column.project_id,
      name: column.name,
      position: column.position
    }
  end
end
