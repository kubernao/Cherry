defmodule Cherry.Workspace do
  import Ecto.Query

  alias Cherry.Repo
  alias Cherry.Workspace.{ActivityEvent, Column, Project, Tag, Task, TaskLink}

  @default_columns ["Backlog", "Next", "Doing", "Done"]
  @deleted_retention_days 5

  def list_projects(opts \\ []) do
    archived = Keyword.get(opts, :archived, false)

    Project
    |> where([p], p.archived == ^archived)
    |> where([p], is_nil(p.deleted_at))
    |> order_by([p], asc: p.title)
    |> Repo.all()
  end

  def get_project!(id_or_slug, opts \\ []) do
    Project
    |> where([p], p.id == ^parse_id(id_or_slug) or p.slug == ^to_string(id_or_slug))
    |> maybe_include_deleted_project(Keyword.get(opts, :include_deleted, false))
    |> preload(
      columns: ^from(c in Column, order_by: c.position),
      tasks: ^from(t in Task, where: is_nil(t.deleted_at), order_by: t.position)
    )
    |> Repo.one!()
  end

  def create_project(attrs, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, project} <- %Project{} |> Project.changeset(attrs) |> Repo.insert() do
        Enum.with_index(@default_columns, fn name, index ->
          create_column!(project, %{name: name, position: index})
        end)

        log!("create", project, opts)
        project
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def update_project(%Project{} = project, attrs, opts \\ []) do
    with {:ok, project} <- project |> Project.changeset(attrs) |> Repo.update() do
      log!("update", project, opts)
      {:ok, project}
    end
  end

  def archive_project(%Project{} = project, opts \\ []) do
    update_project(project, %{archived: true}, opts)
  end

  def restore_project(%Project{} = project, opts \\ []) do
    with {:ok, project} <-
           project
           |> Ecto.Changeset.change(archived: false, deleted_at: nil)
           |> Repo.update() do
      log!("restore", project, Keyword.put(opts, :action, "restore"))
      {:ok, project}
    end
  end

  def delete_project(%Project{} = project, opts \\ []) do
    soft_delete_project(project, utc_now(), opts)
  end

  def list_columns(project_id),
    do: Repo.all(from c in Column, where: c.project_id == ^project_id, order_by: c.position)

  def get_column!(id), do: Repo.get!(Column, id)

  def create_column(%Project{} = project, attrs, opts \\ []) do
    attrs = normalize_column_attrs(attrs)

    position =
      Repo.one(from c in Column, where: c.project_id == ^project.id, select: max(c.position)) ||
        -1

    with {:ok, column} <-
           %Column{}
           |> Column.changeset(
             Map.merge(attrs, %{"project_id" => project.id, "position" => position + 1})
           )
           |> Repo.insert() do
      log!("create", column, opts)
      {:ok, column}
    end
  end

  def create_column!(%Project{} = project, attrs) do
    attrs = normalize_column_attrs(attrs)

    %Column{}
    |> Column.changeset(Map.merge(attrs, %{"project_id" => project.id}))
    |> Repo.insert!()
  end

  def update_column(%Column{} = column, attrs, opts \\ []) do
    attrs = normalize_column_attrs(attrs)

    with {:ok, column} <- column |> Column.changeset(attrs) |> Repo.update() do
      log!("update", column, opts)
      {:ok, column}
    end
  end

  def move_column(%Column{} = column, position, opts \\ []) do
    position = max(parse_id(position), 0)

    Repo.transaction(fn ->
      columns =
        Repo.all(
          from c in Column,
            where: c.project_id == ^column.project_id,
            order_by: [asc: c.position, asc: c.id]
        )

      {moved_columns, other_columns} = Enum.split_with(columns, &(&1.id == column.id))
      moved_column = List.first(moved_columns)

      if is_nil(moved_column) do
        Repo.rollback(:not_found)
      else
        ordered_columns =
          other_columns
          |> List.insert_at(min(position, length(other_columns)), moved_column)
          |> Enum.reject(&is_nil/1)

        renumber_columns(ordered_columns)
        column = get_column!(column.id)
        log!("move", column, Keyword.put(opts, :action, "move"))
        column
      end
    end)
  end

  def delete_column(%Column{} = column, opts \\ []) do
    Repo.transaction(fn ->
      remaining_columns =
        Repo.all(
          from c in Column,
            where: c.project_id == ^column.project_id and c.id != ^column.id,
            order_by: [asc: c.position, asc: c.id]
        )

      case remaining_columns do
        [] ->
          Repo.rollback(:last_column)

        [destination | _] ->
          move_column_tasks(column.id, destination.id)

          with {:ok, column} <- Repo.delete(column) do
            normalize_project_column_positions(column.project_id)
            normalize_column_positions(destination.id)
            log!("delete", column, opts)
            column
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  def list_tasks(opts \\ []) do
    query =
      Task
      |> join(:inner, [t], p in assoc(t, :project))
      |> where([t, p], is_nil(t.deleted_at) and is_nil(p.deleted_at))
      |> where([t, _p], t.archived == ^Keyword.get(opts, :archived, false))
      |> maybe_project(Keyword.get(opts, :project_id))
      |> maybe_due(Keyword.get(opts, :due))
      |> order_by([t, _p], asc: t.position)
      |> preload([:project, :column, :tags])

    Repo.all(query)
  end

  def get_task!(id, opts \\ []),
    do:
      Task
      |> maybe_include_deleted_task(Keyword.get(opts, :include_deleted, false))
      |> Repo.get!(id)
      |> Repo.preload([:project, :column, :tags, :blocking_links, :blocked_by_links])

  def change_task(task \\ %Task{}, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  def create_task(attrs, opts \\ []) do
    attrs = normalize_task_attrs(attrs)

    Repo.transaction(fn ->
      with {:ok, attrs} <- ensure_task_defaults(attrs),
           {:ok, task} <- %Task{} |> Task.changeset(attrs) |> Repo.insert() do
        sync_tags(task, Map.get(attrs, "tags") || Map.get(attrs, :tags) || [])
        task = get_task!(task.id)
        log!("create", task, opts)
        task
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_task(%Task{} = task, attrs, opts \\ []) do
    attrs = normalize_task_attrs(attrs)

    Repo.transaction(fn ->
      with {:ok, task} <- task |> Task.changeset(attrs) |> Repo.update() do
        if Map.has_key?(attrs, "tags") or Map.has_key?(attrs, :tags) do
          sync_tags(task, Map.get(attrs, "tags") || Map.get(attrs, :tags) || [])
        end

        task = get_task!(task.id)
        log!("update", task, opts)
        task
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def move_task(%Task{} = task, column_id, position, opts \\ []) do
    source_column_id = task.column_id
    destination_column_id = parse_id(column_id)
    position = max(position, 0)

    Repo.transaction(fn ->
      with {:ok, moved_task} <-
             task
             |> Task.changeset(%{column_id: destination_column_id, position: position})
             |> Repo.update() do
        normalize_column_positions(source_column_id)
        normalize_column_positions(destination_column_id, moved_task.id, position)
        moved_task = get_task!(moved_task.id)
        log!("move", moved_task, Keyword.put(opts, :action, "move"))

        moved_task
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def complete_task(%Task{} = task, opts \\ []) do
    update_task(task, %{status: "done"}, Keyword.put(opts, :action, "complete"))
  end

  def archive_task(%Task{} = task, opts \\ []) do
    update_task(task, %{archived: true}, Keyword.put(opts, :action, "archive"))
  end

  def delete_task(%Task{} = task, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, task} <- task |> Ecto.Changeset.change(deleted_at: utc_now()) |> Repo.update() do
        normalize_column_positions(task.column_id)
        task = get_task!(task.id, include_deleted: true)
        log!("delete", task, opts)
        task
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def restore_task(%Task{} = task, opts \\ []) do
    with {:ok, task} <-
           task
           |> Ecto.Changeset.change(deleted_at: nil)
           |> Repo.update() do
      normalize_column_positions(task.column_id)
      task = get_task!(task.id)
      log!("restore", task, Keyword.put(opts, :action, "restore"))
      {:ok, task}
    end
  end

  def list_recently_deleted(opts \\ []) do
    since = Keyword.get(opts, :since, deleted_cutoff())

    projects =
      Repo.all(
        from p in Project,
          where: not is_nil(p.deleted_at) and p.deleted_at > ^since,
          order_by: [desc: p.deleted_at],
          limit: 20
      )

    tasks =
      Repo.all(
        from t in Task,
          join: p in assoc(t, :project),
          join: c in assoc(t, :column),
          where:
            not is_nil(t.deleted_at) and t.deleted_at > ^since and
              is_nil(p.deleted_at),
          order_by: [desc: t.deleted_at],
          preload: [project: p, column: c],
          limit: 50
      )

    %{projects: projects, tasks: tasks}
  end

  def purge_deleted_items(now \\ utc_now()) do
    cutoff = deleted_cutoff(now)

    Repo.transaction(fn ->
      {task_count, _} = Repo.delete_all(from t in Task, where: t.deleted_at <= ^cutoff)
      {project_count, _} = Repo.delete_all(from p in Project, where: p.deleted_at <= ^cutoff)

      %{projects: project_count, tasks: task_count}
    end)
  end

  def link_tasks(source_id, target_id, kind \\ "blocks", opts \\ []) do
    with {:ok, link} <-
           %TaskLink{}
           |> TaskLink.changeset(%{
             source_task_id: source_id,
             target_task_id: target_id,
             kind: kind
           })
           |> Repo.insert() do
      log!("link", %{id: link.id, __struct__: TaskLink}, opts)
      {:ok, link}
    end
  end

  def search(query) when is_binary(query) do
    pattern = "%#{String.downcase(query)}%"

    projects =
      Repo.all(
        from p in Project,
          where:
            is_nil(p.deleted_at) and
              (like(fragment("lower(?)", p.title), ^pattern) or
                 like(fragment("lower(coalesce(?, ''))", p.description), ^pattern)),
          limit: 20
      )

    tasks =
      Repo.all(
        from t in Task,
          join: p in assoc(t, :project),
          join: c in assoc(t, :column),
          where:
            is_nil(t.deleted_at) and is_nil(p.deleted_at) and
              (like(fragment("lower(?)", t.title), ^pattern) or
                 like(fragment("lower(coalesce(?, ''))", t.body), ^pattern)),
          preload: [project: p, column: c],
          limit: 50
      )

    %{projects: projects, tasks: tasks}
  end

  def list_activity(limit \\ 50) do
    Repo.all(from a in ActivityEvent, order_by: [desc: a.inserted_at], limit: ^limit)
  end

  def upsert_tag(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()

    Repo.get_by(Tag, name: normalized) ||
      %Tag{} |> Tag.changeset(%{name: normalized, color: "neutral"}) |> Repo.insert!()
  end

  def upsert_tag(%{"name" => name} = attrs) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()
    color = normalize_tag_color(Map.get(attrs, "color") || Map.get(attrs, :color))

    case Repo.get_by(Tag, name: normalized) do
      nil ->
        %Tag{} |> Tag.changeset(%{name: normalized, color: color}) |> Repo.insert!()

      tag ->
        tag
        |> Tag.changeset(%{color: color})
        |> Repo.update!()
    end
  end

  def upsert_tag(%{name: name} = attrs) when is_binary(name) do
    upsert_tag(%{"name" => name, "color" => Map.get(attrs, :color)})
  end

  defp maybe_project(query, nil), do: query
  defp maybe_project(query, project_id), do: where(query, [t, _p], t.project_id == ^project_id)

  defp maybe_include_deleted_project(query, true), do: query
  defp maybe_include_deleted_project(query, false), do: where(query, [p], is_nil(p.deleted_at))

  defp maybe_include_deleted_task(query, true), do: query
  defp maybe_include_deleted_task(query, false), do: where(query, [t], is_nil(t.deleted_at))

  defp maybe_due(query, nil), do: query

  defp maybe_due(query, :upcoming),
    do: where(query, [t], not is_nil(t.due_date) and t.due_date >= ^Date.utc_today())

  defp ensure_task_defaults(attrs) do
    project_id = Map.get(attrs, "project_id") || Map.get(attrs, :project_id)
    column_id = Map.get(attrs, "column_id") || Map.get(attrs, :column_id)

    cond do
      is_nil(project_id) ->
        {:error, Task.changeset(%Task{}, attrs)}

      is_nil(column_id) ->
        column =
          Repo.one!(
            from c in Column, where: c.project_id == ^project_id, order_by: c.position, limit: 1
          )

        ensure_task_defaults(Map.put(attrs, "column_id", column.id))

      is_nil(Map.get(attrs, "position") || Map.get(attrs, :position)) ->
        max_position =
          Repo.one(from t in Task, where: t.column_id == ^column_id, select: max(t.position)) ||
            -1

        {:ok, Map.put(attrs, "position", max_position + 1)}

      true ->
        {:ok, attrs}
    end
  end

  defp normalize_task_attrs(attrs) do
    attrs
    |> Enum.into(%{})
    |> normalize_tags_json()
    |> parse_due_date()
  end

  defp normalize_tags_json(%{"tags_json" => tags_json} = attrs) when is_binary(tags_json) do
    case Jason.decode(tags_json) do
      {:ok, tags} when is_list(tags) -> Map.put(attrs, "tags", tags)
      _ -> attrs
    end
  end

  defp normalize_tags_json(%{tags_json: tags_json} = attrs) when is_binary(tags_json) do
    case Jason.decode(tags_json) do
      {:ok, tags} when is_list(tags) -> Map.put(attrs, :tags, tags)
      _ -> attrs
    end
  end

  defp normalize_tags_json(attrs), do: attrs

  defp normalize_column_attrs(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp parse_due_date(%{"due_date" => ""} = attrs), do: Map.put(attrs, "due_date", nil)
  defp parse_due_date(%{due_date: ""} = attrs), do: Map.put(attrs, :due_date, nil)
  defp parse_due_date(attrs), do: attrs

  defp sync_tags(task, tags) when is_binary(tags),
    do: sync_tags(task, String.split(tags, ",", trim: true))

  defp sync_tags(task, tags) when is_list(tags) do
    tag_records =
      tags
      |> Enum.map(&normalize_tag_attrs/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.name)
      |> Enum.map(&upsert_tag/1)

    task
    |> Repo.preload(:tags)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, tag_records)
    |> Repo.update!()
  end

  defp normalize_tag_attrs(%{"name" => name} = tag) when is_binary(name) do
    name = name |> String.trim() |> String.downcase()

    if name == "" do
      nil
    else
      %{
        name: name,
        color: normalize_tag_color(Map.get(tag, "color") || Map.get(tag, :color))
      }
    end
  end

  defp normalize_tag_attrs(%{name: name} = tag) when is_binary(name) do
    normalize_tag_attrs(%{"name" => name, "color" => Map.get(tag, :color)})
  end

  defp normalize_tag_attrs(tag) when is_binary(tag) do
    name = tag |> String.trim() |> String.downcase()

    if name == "" do
      nil
    else
      %{name: name, color: "neutral"}
    end
  end

  defp normalize_tag_attrs(_tag), do: nil

  defp normalize_tag_color(color)
       when color in ["neutral", "rose", "amber", "emerald", "sky", "violet"],
       do: color

  defp normalize_tag_color(_color), do: "neutral"

  defp normalize_column_positions(column_id) do
    column_id
    |> column_tasks()
    |> renumber_tasks()
  end

  defp normalize_column_positions(column_id, moved_task_id, target_position) do
    tasks = column_tasks(column_id)
    {moved_tasks, other_tasks} = Enum.split_with(tasks, &(&1.id == moved_task_id))
    moved_task = List.first(moved_tasks)

    other_tasks
    |> List.insert_at(min(target_position, length(other_tasks)), moved_task)
    |> Enum.reject(&is_nil/1)
    |> renumber_tasks()
  end

  defp column_tasks(column_id) do
    Repo.all(
      from t in Task,
        where: t.column_id == ^column_id and t.archived == false and is_nil(t.deleted_at),
        order_by: [asc: t.position, asc: t.updated_at, asc: t.id]
    )
  end

  defp renumber_tasks(tasks) do
    tasks
    |> Enum.with_index()
    |> Enum.each(fn {task, position} ->
      task
      |> Ecto.Changeset.change(position: position)
      |> Repo.update!()
    end)
  end

  defp move_column_tasks(source_column_id, destination_column_id) do
    next_position =
      Repo.one(
        from t in Task,
          where:
            t.column_id == ^destination_column_id and t.archived == false and is_nil(t.deleted_at),
          select: max(t.position)
      ) || -1

    source_column_id
    |> column_tasks()
    |> Enum.with_index(next_position + 1)
    |> Enum.each(fn {task, position} ->
      task
      |> Ecto.Changeset.change(column_id: destination_column_id, position: position)
      |> Repo.update!()
    end)
  end

  defp normalize_project_column_positions(project_id) do
    Repo.all(
      from c in Column,
        where: c.project_id == ^project_id,
        order_by: [asc: c.position, asc: c.id]
    )
    |> renumber_columns()
  end

  defp renumber_columns(columns) do
    columns
    |> Enum.each(fn column ->
      column
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.force_change(:position, -column.id)
      |> Repo.update!()
    end)

    columns
    |> Enum.with_index()
    |> Enum.each(fn {column, position} ->
      column
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.force_change(:position, position)
      |> Repo.update!()
    end)
  end

  defp soft_delete_project(%Project{} = project, deleted_at, opts) do
    with {:ok, project} <-
           project |> Ecto.Changeset.change(deleted_at: deleted_at) |> Repo.update() do
      log!("delete", project, opts)
      {:ok, project}
    end
  end

  defp deleted_cutoff(now \\ utc_now()) do
    DateTime.add(now, -@deleted_retention_days, :day)
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp log!(action, entity, opts) do
    action = Keyword.get(opts, :action, action)

    entity_type =
      entity.__struct__
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    %ActivityEvent{}
    |> ActivityEvent.changeset(%{
      user_id: Keyword.get(opts, :user_id),
      actor: Keyword.get(opts, :actor, "web"),
      action: action,
      entity_type: entity_type,
      entity_id: entity.id,
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> Repo.insert!()
  end

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> -1
    end
  end
end
