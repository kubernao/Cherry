defmodule CherryWeb.UiLiveTest do
  use CherryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Cherry.{Accounts, Workspace}

  defp log_in(conn) do
    user =
      Accounts.ensure_owner!(%{email: "owner@example.com", password: "super-secret-password"})

    conn = Plug.Test.init_test_session(conn, user_id: user.id)
    {conn, user}
  end

  defp project_with_tasks do
    {:ok, project} =
      Workspace.create_project(%{
        "title" => "Client Portal",
        "description" => "# Notes\nKeep scope close."
      })

    [backlog, next | _] = Workspace.list_columns(project.id)

    {:ok, first} =
      Workspace.create_task(%{
        "project_id" => project.id,
        "column_id" => backlog.id,
        "title" => "Draft scope",
        "tags" => "writing"
      })

    {:ok, second} =
      Workspace.create_task(%{
        "project_id" => project.id,
        "column_id" => backlog.id,
        "title" => "Review copy"
      })

    %{project: project, backlog: backlog, next: next, first: first, second: second}
  end

  test "dashboard renders redesigned project controls", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#project-search-form")
    assert has_element?(view, "#project-search.cherry-search-field")
    assert has_element?(view, "#new-project-button")
    refute has_element?(view, "#project-form")
    assert has_element?(view, "#project-card-#{project.id}")
  end

  test "dashboard plus opens and closes new project modal", %{conn: conn} do
    {conn, _user} = log_in(conn)
    project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#new-project-button") |> render_click()
    assert has_element?(view, "#dashboard-modal")
    assert has_element?(view, "#project-form.cherry-form")
    assert has_element?(view, "#project_description.cherry-notes-field")
    assert has_element?(view, "#create-project-button")

    view |> element("#close-dashboard-modal") |> render_click()
    refute has_element?(view, "#dashboard-modal")
    refute has_element?(view, "#project-form")
  end

  test "project board renders simplified columns, cards, menu, and alternate views", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, backlog: backlog, first: first} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#task-board")
    assert has_element?(view, "#column-#{backlog.id}-tasks")
    assert has_element?(view, "#task-#{first.id}")
    refute has_element?(view, "#task-#{first.id}-move")
    assert has_element?(view, "#project-waffle")
    assert has_element?(view, "#project-view-switcher")

    view |> element("#view-list") |> render_click()
    assert has_element?(view, "#task-list-view")

    view |> element("#view-calendar") |> render_click()
    assert has_element?(view, "#task-calendar-view")
  end

  test "project waffle opens and closes tool modals", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#project-waffle") |> render_click()
    assert has_element?(view, "#project-tools-menu")

    view |> element("#open-new_task-modal") |> render_click()
    assert has_element?(view, "#project-modal")
    assert has_element?(view, "#new-task-modal")
    assert has_element?(view, "#task-form.cherry-form")
    assert has_element?(view, "#task-tags-editor")
    assert has_element?(view, "#task-tags-editor-value[name='task[tags_json]']")

    view |> element("#close-project-modal") |> render_click()
    refute has_element?(view, "#project-modal")

    view |> element("#project-waffle") |> render_click()
    view |> element("#open-notes-modal") |> render_click()
    assert has_element?(view, "#project-notes")

    view |> element("#close-project-modal") |> render_click()
    view |> element("#project-waffle") |> render_click()
    view |> element("#open-activity-modal") |> render_click()
    assert has_element?(view, "#recent-activity")
  end

  test "project columns can be added, renamed, and removed", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, backlog: backlog, next: next, first: first} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#project-waffle") |> render_click()
    view |> element("#open-columns-modal") |> render_click()

    assert has_element?(view, "#columns-modal")
    assert has_element?(view, "#column-form")
    assert has_element?(view, "#column-manager-#{backlog.id}")

    view
    |> element("#column-form")
    |> render_submit(%{"column" => %{"name" => "Blocked"}})

    assert blocked = Workspace.list_columns(project.id) |> Enum.find(&(&1.name == "Blocked"))
    assert has_element?(view, "#column-manager-#{blocked.id}")

    view |> element("#edit-column-#{blocked.id}") |> render_click()
    assert has_element?(view, "#edit-column-form-#{blocked.id}")

    view
    |> element("#edit-column-form-#{blocked.id}")
    |> render_submit(%{"column" => %{"id" => blocked.id, "name" => "Waiting"}})

    assert Workspace.get_column!(blocked.id).name == "Waiting"

    view |> element("#delete-column-#{next.id}") |> render_click()

    assert_raise Ecto.NoResultsError, fn -> Workspace.get_column!(next.id) end
    assert Workspace.get_task!(first.id).column_id == backlog.id
  end

  test "double-clicking a card opens details modal before editing task fields", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, first: first, next: next} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    render_hook(view, "view_task", %{"task_id" => first.id})

    assert has_element?(view, "#project-modal")
    assert has_element?(view, "#view-task-modal")
    assert has_element?(view, "#view-task-#{first.id}-title")
    assert has_element?(view, "#view-task-meta")
    assert has_element?(view, "#edit-viewed-task-button")
    refute has_element?(view, "#edit-task-form")

    view |> element("#edit-viewed-task-button") |> render_click()

    assert has_element?(view, "#edit-task-modal")
    assert has_element?(view, "#edit-task-form")
    assert has_element?(view, "#task_body.cherry-notes-field")
    assert has_element?(view, "#edit-task-tags-editor")

    view
    |> element("#edit-task-form")
    |> render_submit(%{
      "task" => %{
        "id" => first.id,
        "title" => "Draft plan",
        "body" => "Updated notes",
        "column_id" => next.id,
        "priority" => "high",
        "status" => "in_progress",
        "due_date" => "2026-06-20",
        "tags_json" =>
          Jason.encode!([
            %{name: "planning", color: "emerald"},
            %{name: "client", color: "sky"}
          ])
      }
    })

    assert task = Workspace.get_task!(first.id)
    assert task.title == "Draft plan"
    assert task.body == "Updated notes"
    assert task.column_id == next.id
    assert task.priority == "high"
    assert task.status == "in_progress"
    assert task.due_date == ~D[2026-06-20]
    assert Enum.map(task.tags, & &1.name) == ["planning", "client"]
    assert Enum.map(task.tags, & &1.color) == ["emerald", "sky"]
  end

  test "drag move event persists destination column and requested position", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, backlog: backlog, first: first, second: second} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    render_hook(view, "move_task", %{
      "task_id" => second.id,
      "column_id" => backlog.id,
      "position" => 0
    })

    second_id = second.id
    first_id = first.id
    backlog_id = backlog.id

    assert %{id: ^second_id, position: 0, column_id: ^backlog_id} =
             Workspace.get_task!(second.id)

    assert %{id: ^first_id, position: 1, column_id: ^backlog_id} =
             Workspace.get_task!(first.id)
  end

  test "drag column event persists requested board position", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, backlog: backlog, next: next} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    render_hook(view, "move_column", %{
      "column_id" => next.id,
      "position" => 0
    })

    assert Enum.map(Workspace.list_columns(project.id), &{&1.id, &1.position}) |> Enum.take(2) ==
             [
               {next.id, 0},
               {backlog.id, 1}
             ]
  end

  test "fallback move without position appends to target column", %{conn: conn} do
    {conn, _user} = log_in(conn)
    %{project: project, next: next, first: first} = project_with_tasks()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    render_hook(view, "move_task", %{
      "task_id" => first.id,
      "column_id" => next.id
    })

    next_id = next.id
    assert %{position: 0, column_id: ^next_id} = Workspace.get_task!(first.id)
  end

  test "sign in page renders expected form controls", %{conn: conn} do
    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ ~s(id="login-form")
    assert html_response(conn, 200) =~ ~s(id="user_email")
    assert html_response(conn, 200) =~ ~s(id="user_password")
    assert html_response(conn, 200) =~ ~s(id="login-button")
  end
end
