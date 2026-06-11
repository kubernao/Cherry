defmodule Cherry.WorkspaceTest do
  use Cherry.DataCase

  alias Cherry.{Repo, Workspace}

  test "creates projects with default columns and tasks with tags" do
    assert {:ok, project} =
             Workspace.create_project(%{"title" => "Client Portal", "description" => "# Notes"})

    columns = Workspace.list_columns(project.id)
    assert Enum.map(columns, & &1.name) == ["Backlog", "Next", "Doing", "Done"]

    assert {:ok, task} =
             Workspace.create_task(%{
               "project_id" => project.id,
               "title" => "Draft scope",
               "body" => "Write the **first** pass",
               "tags" => "writing, client"
             })

    assert task.column_id == hd(columns).id
    assert Enum.map(task.tags, & &1.name) == ["writing", "client"]

    assert %{projects: [found_project], tasks: []} = Workspace.search("client")
    assert found_project.id == project.id

    assert %{tasks: [found_task]} = Workspace.search("scope")
    assert found_task.id == task.id
  end

  test "updates, archives, restores, and soft deletes projects" do
    {:ok, project} = Workspace.create_project(%{"title" => "Ops"})

    assert {:ok, project} =
             Workspace.update_project(project, %{
               "title" => "Operations",
               "description" => "Runbook",
               "status" => "paused",
               "priority" => "high"
             })

    assert project.title == "Operations"
    assert project.description == "Runbook"
    assert project.status == "paused"
    assert project.priority == "high"

    assert {:ok, project} = Workspace.archive_project(project)
    assert project.archived

    assert {:ok, project} = Workspace.restore_project(project)
    refute project.archived

    assert {:ok, deleted_project} = Workspace.delete_project(project)
    assert deleted_project.deleted_at
    assert_raise Ecto.NoResultsError, fn -> Workspace.get_project!(project.id) end

    assert Workspace.get_project!(project.id, include_deleted: true).deleted_at
    assert Workspace.list_projects() == []

    assert %{projects: [recoverable], tasks: []} = Workspace.list_recently_deleted()
    assert recoverable.id == project.id

    assert {:ok, restored_project} = Workspace.restore_project(deleted_project)
    refute restored_project.deleted_at
    assert Workspace.get_project!(project.id).id == project.id
  end

  test "soft deletes, restores, and purges task cards" do
    {:ok, project} = Workspace.create_project(%{"title" => "Board"})

    {:ok, task} =
      Workspace.create_task(%{
        "project_id" => project.id,
        "title" => "Recover me"
      })

    assert {:ok, deleted_task} = Workspace.delete_task(task)
    assert deleted_task.deleted_at
    assert_raise Ecto.NoResultsError, fn -> Workspace.get_task!(task.id) end

    assert %{tasks: [recoverable_task]} = Workspace.list_recently_deleted()
    assert recoverable_task.id == task.id

    assert {:ok, restored_task} = Workspace.restore_task(deleted_task)
    refute restored_task.deleted_at
    assert Workspace.get_task!(task.id).id == task.id

    assert {:ok, deleted_task} = Workspace.delete_task(restored_task)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old_deleted_at = DateTime.add(now, -6, :day)

    deleted_task
    |> Ecto.Changeset.change(deleted_at: old_deleted_at)
    |> Repo.update!()

    assert {:ok, %{tasks: 1, projects: 0}} = Workspace.purge_deleted_items(now)

    assert_raise Ecto.NoResultsError, fn ->
      Workspace.get_task!(task.id, include_deleted: true)
    end
  end

  test "purges projects after the recently deleted retention window" do
    {:ok, project} = Workspace.create_project(%{"title" => "Expired"})
    assert {:ok, deleted_project} = Workspace.delete_project(project)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old_deleted_at = DateTime.add(now, -6, :day)

    deleted_project
    |> Ecto.Changeset.change(deleted_at: old_deleted_at)
    |> Repo.update!()

    assert {:ok, %{projects: 1, tasks: 0}} = Workspace.purge_deleted_items(now)

    assert_raise Ecto.NoResultsError, fn ->
      Workspace.get_project!(project.id, include_deleted: true)
    end
  end

  test "creates and updates task tags with colors from structured form params" do
    {:ok, project} = Workspace.create_project(%{"title" => "Launch"})

    assert {:ok, task} =
             Workspace.create_task(%{
               "project_id" => project.id,
               "title" => "Plan launch",
               "tags_json" =>
                 Jason.encode!([
                   %{name: "Planning", color: "emerald"},
                   %{name: "Client", color: "sky"}
                 ])
             })

    assert Enum.map(task.tags, &{&1.name, &1.color}) == [
             {"planning", "emerald"},
             {"client", "sky"}
           ]

    assert {:ok, task} =
             Workspace.update_task(task, %{
               "tags_json" => Jason.encode!([%{name: "planning", color: "violet"}])
             })

    assert Enum.map(task.tags, &{&1.name, &1.color}) == [{"planning", "violet"}]
  end

  test "prevents task dependency self links" do
    {:ok, project} = Workspace.create_project(%{"title" => "Launch"})
    {:ok, task} = Workspace.create_task(%{"project_id" => project.id, "title" => "Ship"})

    assert {:error, changeset} = Workspace.link_tasks(task.id, task.id)
    assert %{source_task_id: [_]} = errors_on(changeset)
  end

  test "creates, renames, and deletes columns while preserving tasks" do
    {:ok, project} = Workspace.create_project(%{"title" => "Board"})
    [backlog, next | _] = Workspace.list_columns(project.id)

    assert {:ok, blocked} = Workspace.create_column(project, %{"name" => "Blocked"})
    assert blocked.position == 4

    assert {:ok, blocked} = Workspace.update_column(blocked, %{"name" => "Waiting"})
    assert blocked.name == "Waiting"

    {:ok, task} =
      Workspace.create_task(%{
        "project_id" => project.id,
        "column_id" => next.id,
        "title" => "Keep me"
      })

    assert {:ok, _column} = Workspace.delete_column(next)
    assert Workspace.get_task!(task.id).column_id == backlog.id

    assert Enum.map(Workspace.list_columns(project.id), & &1.position) == [0, 1, 2, 3]
  end

  test "moves columns to requested positions" do
    {:ok, project} = Workspace.create_project(%{"title" => "Ordered Board"})
    [backlog, next, doing, done] = Workspace.list_columns(project.id)

    assert {:ok, moved} = Workspace.move_column(done, 0)
    assert moved.id == done.id

    assert Enum.map(Workspace.list_columns(project.id), &{&1.id, &1.position}) == [
             {done.id, 0},
             {backlog.id, 1},
             {next.id, 2},
             {doing.id, 3}
           ]

    assert {:ok, moved} = Workspace.move_column(done, 3)
    assert moved.id == done.id

    assert Enum.map(Workspace.list_columns(project.id), &{&1.id, &1.position}) == [
             {backlog.id, 0},
             {next.id, 1},
             {doing.id, 2},
             {done.id, 3}
           ]
  end
end
