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

  test "archives, restores, and deletes projects", %{conn: conn, token: token} do
    conn =
      conn
      |> auth(token)
      |> post(~p"/api/v1/projects", %{
        "project" => %{"title" => "Project CRUD", "description" => "Initial"}
      })

    assert %{"project" => %{"id" => project_id}} = json_response(conn, 201)

    conn =
      build_conn()
      |> auth(token)
      |> patch(~p"/api/v1/projects/#{project_id}", %{
        "project" => %{
          "title" => "Project CRUD Updated",
          "status" => "paused",
          "priority" => "urgent"
        }
      })

    assert %{
             "project" => %{
               "title" => "Project CRUD Updated",
               "status" => "paused",
               "priority" => "urgent"
             }
           } = json_response(conn, 200)

    conn = build_conn() |> auth(token) |> post(~p"/api/v1/projects/#{project_id}/archive")
    assert %{"project" => %{"archived" => true}} = json_response(conn, 200)

    conn = build_conn() |> auth(token) |> post(~p"/api/v1/projects/#{project_id}/restore")
    assert %{"project" => %{"archived" => false}} = json_response(conn, 200)

    conn = build_conn() |> auth(token) |> delete(~p"/api/v1/projects/#{project_id}")
    assert response(conn, 204) == ""
    assert_raise Ecto.NoResultsError, fn -> Workspace.get_project!(project_id) end
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")
end
