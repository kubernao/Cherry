defmodule CherryWeb.ApiControllerTest do
  use CherryWeb.ConnCase

  alias Cherry.{Accounts, Workspace}

  setup do
    user =
      Accounts.ensure_owner!(%{email: "owner@example.com", password: "super-secret-password"})

    {:ok, raw, _token} =
      Accounts.create_api_token(user, %{name: "test", scopes: "read,write,admin"})

    %{token: raw}
  end

  test "rejects missing bearer token", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/projects")
    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "creates and updates projects and tasks", %{conn: conn, token: token} do
    conn =
      conn
      |> auth(token)
      |> post(~p"/api/v1/projects", %{
        "project" => %{"title" => "Agent Work", "description" => "CLI controlled"}
      })

    assert %{"project" => %{"id" => project_id, "title" => "Agent Work"}} =
             json_response(conn, 201)

    project = Workspace.get_project!(project_id)
    column = hd(project.columns)

    conn =
      build_conn()
      |> auth(token)
      |> post(~p"/api/v1/tasks", %{
        "task" => %{"project_id" => project_id, "column_id" => column.id, "title" => "Read API"}
      })

    assert %{"task" => %{"id" => task_id, "title" => "Read API"}} = json_response(conn, 201)

    conn = build_conn() |> auth(token) |> post(~p"/api/v1/tasks/#{task_id}/done")
    assert %{"task" => %{"status" => "done"}} = json_response(conn, 200)
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")
end
