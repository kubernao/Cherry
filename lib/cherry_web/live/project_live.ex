defmodule CherryWeb.ProjectLive do
  use CherryWeb, :live_view

  alias Cherry.Workspace
  alias CherryWeb.Markdown

  def mount(%{"id" => id}, _session, socket) do
    project = Workspace.get_project!(id)

    {:ok,
     socket
     |> assign(:page_title, project.title)
     |> assign(:view, :board)
     |> assign(:active_modal, nil)
     |> assign(:project_menu_open?, false)
     |> assign(:viewing_task, nil)
     |> assign(:editing_task, nil)
     |> assign(:edit_task_form, nil)
     |> assign(:task_form, task_form(project))
     |> assign(:column_form, column_form())
     |> assign(:editing_column_id, nil)
     |> assign(:edit_column_form, nil)
     |> assign(:project, project)
     |> load_board()}
  end

  def handle_event("set_view", %{"view" => view}, socket)
      when view in ["board", "list", "calendar"] do
    {:noreply, assign(socket, :view, String.to_existing_atom(view))}
  end

  def handle_event("create_task", %{"task" => attrs}, socket) do
    attrs = Map.put(attrs, "project_id", socket.assigns.project.id)

    case Workspace.create_task(attrs, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created.")
         |> assign(:active_modal, nil)
         |> assign(:task_form, task_form(socket.assigns.project))
         |> push_event("reset-task-form", %{})
         |> load_board()}

      {:error, changeset} ->
        {:noreply, assign(socket, :task_form, to_form(changeset, as: :task))}
    end
  end

  def handle_event("toggle_project_menu", _params, socket) do
    {:noreply, update(socket, :project_menu_open?, &(!&1))}
  end

  def handle_event("open_modal", %{"modal" => modal}, socket)
      when modal in ["new_task", "columns", "notes", "activity"] do
    {:noreply,
     assign(socket, active_modal: String.to_existing_atom(modal), project_menu_open?: false)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     assign(socket,
       active_modal: nil,
       project_menu_open?: false,
       viewing_task: nil,
       editing_task: nil,
       edit_task_form: nil,
       editing_column_id: nil,
       edit_column_form: nil
     )}
  end

  def handle_event("create_column", %{"column" => attrs}, socket) do
    case Workspace.create_column(socket.assigns.project, attrs,
           actor: "web",
           user_id: socket.assigns.current_user.id
         ) do
      {:ok, _column} ->
        {:noreply,
         socket
         |> assign(:column_form, column_form())
         |> put_flash(:info, "Column added.")
         |> load_board()}

      {:error, changeset} ->
        {:noreply, assign(socket, :column_form, to_form(changeset, as: :column))}
    end
  end

  def handle_event("edit_column", %{"id" => id}, socket) do
    column = project_column!(socket, id)

    {:noreply,
     assign(socket,
       editing_column_id: column.id,
       edit_column_form: edit_column_form(column)
     )}
  end

  def handle_event("cancel_column_edit", _params, socket) do
    {:noreply, assign(socket, editing_column_id: nil, edit_column_form: nil)}
  end

  def handle_event("update_column", %{"column" => attrs}, socket) do
    column = project_column!(socket, attrs["id"])

    case Workspace.update_column(column, attrs,
           actor: "web",
           user_id: socket.assigns.current_user.id
         ) do
      {:ok, _column} ->
        {:noreply,
         socket
         |> assign(editing_column_id: nil, edit_column_form: nil)
         |> put_flash(:info, "Column updated.")
         |> load_board()}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_column_form, to_form(changeset, as: :column))}
    end
  end

  def handle_event("delete_column", %{"id" => id}, socket) do
    column = project_column!(socket, id)

    case Workspace.delete_column(column, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _column} ->
        {:noreply,
         socket
         |> assign(editing_column_id: nil, edit_column_form: nil)
         |> put_flash(:info, "Column removed.")
         |> load_board()}

      {:error, :last_column} ->
        {:noreply, put_flash(socket, :error, "A project needs at least one column.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Column could not be removed.")}
    end
  end

  def handle_event("move_column", %{"column_id" => column_id, "position" => position}, socket) do
    column = project_column!(socket, column_id)

    case Workspace.move_column(column, parse_position(position),
           actor: "web",
           user_id: socket.assigns.current_user.id
         ) do
      {:ok, _column} ->
        {:noreply, load_board(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Column could not be moved.")}
    end
  end

  def handle_event("edit_task", %{"task_id" => task_id}, socket) do
    task = Workspace.get_task!(task_id)

    {:noreply,
     assign(socket,
       active_modal: :edit_task,
       project_menu_open?: false,
       viewing_task: nil,
       editing_task: task,
       edit_task_form: edit_task_form(task)
     )}
  end

  def handle_event("view_task", %{"task_id" => task_id}, socket) do
    task = Workspace.get_task!(task_id)

    {:noreply,
     assign(socket,
       active_modal: :view_task,
       project_menu_open?: false,
       viewing_task: task,
       editing_task: nil,
       edit_task_form: nil
     )}
  end

  def handle_event("update_task", %{"task" => attrs}, socket) do
    task = socket.assigns.editing_task || Workspace.get_task!(attrs["id"])

    case Workspace.update_task(task, attrs,
           actor: "web",
           user_id: socket.assigns.current_user.id
         ) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(active_modal: nil, viewing_task: nil, editing_task: nil, edit_task_form: nil)
         |> load_board()}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_task_form, to_form(changeset, as: :task))}
    end
  end

  def handle_event(
        "move_task",
        %{"task_id" => task_id, "column_id" => column_id, "position" => position},
        socket
      ) do
    task = Workspace.get_task!(task_id)
    move_task(socket, task, column_id, parse_position(position))
  end

  def handle_event("move_task", %{"task_id" => task_id, "column_id" => column_id}, socket) do
    task = Workspace.get_task!(task_id)

    position =
      socket.assigns.tasks_by_column
      |> Map.get(parse_id(column_id), [])
      |> Enum.count()

    move_task(socket, task, column_id, position)
  end

  def handle_event("archive_task", %{"id" => id}, socket) do
    {:ok, _task} =
      Workspace.get_task!(id)
      |> Workspace.archive_task(actor: "web", user_id: socket.assigns.current_user.id)

    {:noreply, load_board(socket)}
  end

  defp move_task(socket, task, column_id, position) do
    {:ok, _task} =
      Workspace.move_task(task, column_id, position,
        actor: "web",
        user_id: socket.assigns.current_user.id
      )

    {:noreply, load_board(socket)}
  end

  defp parse_position(position) when is_integer(position), do: max(position, 0)

  defp parse_position(position) when is_binary(position) do
    case Integer.parse(position) do
      {position, ""} -> max(position, 0)
      _ -> 0
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> -1
    end
  end

  defp load_board(socket) do
    project = Workspace.get_project!(socket.assigns.project.id)
    columns = Workspace.list_columns(project.id)
    tasks = Workspace.list_tasks(project_id: project.id)

    socket
    |> assign(:project, project)
    |> assign(:columns, columns)
    |> assign(:tasks, tasks)
    |> assign(:tasks_by_column, Enum.group_by(tasks, & &1.column_id))
    |> assign(:activity, Workspace.list_activity(20))
  end

  defp task_form(project) do
    first_column = Workspace.list_columns(project.id) |> List.first()

    to_form(
      %{
        "title" => "",
        "body" => "",
        "priority" => "normal",
        "status" => "open",
        "due_date" => "",
        "column_id" => first_column && first_column.id,
        "tags_json" => "[]"
      },
      as: :task
    )
  end

  defp column_form do
    to_form(%{"name" => ""}, as: :column)
  end

  defp edit_column_form(column) do
    to_form(%{"id" => column.id, "name" => column.name, "position" => column.position},
      as: :column
    )
  end

  defp edit_task_form(task) do
    to_form(
      %{
        "id" => task.id,
        "title" => task.title,
        "body" => task.body || "",
        "priority" => task.priority,
        "status" => task.status,
        "due_date" => task.due_date && Date.to_iso8601(task.due_date),
        "column_id" => task.column_id,
        "tags_json" => tags_json(task.tags)
      },
      as: :task
    )
  end

  defp tags_json(tags) do
    tags
    |> Enum.map(&%{name: &1.name, color: &1.color})
    |> Jason.encode!()
  end

  defp tag_color_options do
    [
      {"Stone", "neutral"},
      {"Rose", "rose"},
      {"Amber", "amber"},
      {"Emerald", "emerald"},
      {"Sky", "sky"},
      {"Violet", "violet"}
    ]
  end

  defp tag_input(assigns) do
    assigns = assign(assigns, :color_options, tag_color_options())

    ~H"""
    <div
      id={@id}
      phx-hook="TagEditor"
      phx-update="ignore"
      data-initial-tags={@form[:tags_json].value || "[]"}
      class="space-y-2"
    >
      <label for={"#{@id}-input"} class="cherry-label">{@label}</label>
      <input
        id={"#{@id}-value"}
        type="hidden"
        name={"#{@form.name}[tags_json]"}
        value={@form[:tags_json].value || "[]"}
        data-tag-editor-value
      />
      <div
        data-tag-list
        class="hidden min-h-9 flex-wrap gap-2 rounded-lg border border-stone-200 bg-white/70 p-2 dark:border-stone-700 dark:bg-stone-900/70"
      >
      </div>
      <div class="flex items-center gap-2 rounded-lg border border-stone-300 bg-white/90 px-2.5 py-2 shadow-sm transition focus-within:border-rose-500 focus-within:ring-3 focus-within:ring-rose-500/15 dark:border-stone-700 dark:bg-stone-900/90 dark:focus-within:border-rose-400 dark:focus-within:ring-rose-400/20">
        <input
          id={"#{@id}-input"}
          type="text"
          data-tag-input
          placeholder="Type tag, press space or enter"
          autocomplete="off"
          class="min-w-0 flex-1 bg-transparent text-sm text-stone-950 outline-none placeholder:text-stone-500 dark:text-stone-50 dark:placeholder:text-stone-500"
        />
        <select
          id={"#{@id}-color"}
          data-tag-color-select
          aria-label="Tag color"
          class="shrink-0 rounded-md border border-stone-200 bg-stone-50 px-2 py-1 text-xs font-semibold text-stone-600 outline-none transition hover:border-stone-300 focus:border-rose-500 dark:border-stone-700 dark:bg-stone-800 dark:text-stone-200"
        >
          <option :for={{label, value} <- @color_options} value={value}>{label}</option>
        </select>
      </div>
    </div>
    """
  end

  defp tag_color_class("rose"),
    do:
      "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900/70 dark:bg-rose-950/50 dark:text-rose-300"

  defp tag_color_class("amber"),
    do:
      "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900/70 dark:bg-amber-950/50 dark:text-amber-300"

  defp tag_color_class("emerald"),
    do:
      "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/70 dark:bg-emerald-950/50 dark:text-emerald-300"

  defp tag_color_class("sky"),
    do:
      "border-sky-200 bg-sky-50 text-sky-700 dark:border-sky-900/70 dark:bg-sky-950/50 dark:text-sky-300"

  defp tag_color_class("violet"),
    do:
      "border-violet-200 bg-violet-50 text-violet-700 dark:border-violet-900/70 dark:bg-violet-950/50 dark:text-violet-300"

  defp tag_color_class(_color),
    do:
      "border-stone-200 bg-stone-50 text-stone-700 dark:border-stone-700 dark:bg-stone-800 dark:text-stone-300"

  defp project_column!(socket, id) do
    column = Workspace.get_column!(id)

    if column.project_id == socket.assigns.project.id do
      column
    else
      raise Ecto.NoResultsError, queryable: Cherry.Workspace.Column
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <section
        class="min-w-0 space-y-5 sm:space-y-6"
        phx-window-keydown="close_modal"
        phx-key="escape"
      >
        <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div class="min-w-0">
            <.link
              navigate={~p"/"}
              id="back-to-projects"
              class="inline-flex items-center gap-2 text-sm font-medium text-stone-500 transition hover:text-stone-950 dark:text-stone-400 dark:hover:text-stone-100"
            >
              <.icon name="hero-arrow-left" class="size-4" /> Projects
            </.link>
            <h1 class="mt-3 break-words text-2xl font-semibold tracking-normal text-stone-950 sm:text-3xl dark:text-stone-50">
              {@project.title}
            </h1>
            <div class="mt-3 flex flex-wrap gap-2 text-xs font-medium">
              <span class="rounded-md border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-emerald-700 dark:border-emerald-900/70 dark:bg-emerald-950/50 dark:text-emerald-300">
                {@project.status}
              </span>
              <span class="rounded-md border border-rose-200 bg-rose-50 px-2.5 py-1 text-rose-700 dark:border-rose-900/70 dark:bg-rose-950/50 dark:text-rose-300">
                {@project.priority}
              </span>
              <span class="rounded-md border border-stone-200 bg-white/80 px-2.5 py-1 text-stone-600 dark:border-stone-700 dark:bg-stone-900/80 dark:text-stone-300">
                {Enum.count(@tasks)} tasks
              </span>
            </div>
          </div>

          <div class="flex w-full flex-col gap-3 sm:flex-row sm:items-center lg:w-auto">
            <div
              id="project-view-switcher"
              class="grid w-full grid-cols-3 rounded-xl border border-stone-200 bg-white/70 p-1 shadow-sm sm:w-auto dark:border-stone-700 dark:bg-stone-900/70"
            >
              <button
                :for={{label, view} <- [{"Board", "board"}, {"List", "list"}, {"Dates", "calendar"}]}
                id={"view-#{view}"}
                class={[
                  "rounded-lg px-3 py-2 text-sm font-semibold transition sm:px-4",
                  @view == String.to_existing_atom(view) &&
                    "bg-stone-950 text-white shadow-sm shadow-stone-900/20 dark:bg-stone-50 dark:text-stone-950",
                  @view != String.to_existing_atom(view) &&
                    "text-stone-500 hover:bg-stone-100 hover:text-stone-950 dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                ]}
                phx-click="set_view"
                phx-value-view={view}
              >
                {label}
              </button>
            </div>

            <div class="relative sm:shrink-0">
              <button
                id="project-waffle"
                type="button"
                class="grid h-11 w-full place-items-center rounded-xl border border-stone-200 bg-white/80 text-stone-600 shadow-sm transition hover:-translate-y-0.5 hover:border-stone-300 hover:text-stone-950 sm:size-11 dark:border-stone-700 dark:bg-stone-900/80 dark:text-stone-300 dark:hover:border-stone-600 dark:hover:text-stone-50"
                phx-click="toggle_project_menu"
                aria-label="Open project tools"
              >
                <.icon name="hero-squares-2x2" class="size-5" />
              </button>

              <div
                :if={@project_menu_open?}
                id="project-tools-menu"
                class="absolute right-0 z-30 mt-2 w-full min-w-56 overflow-hidden rounded-xl border border-stone-200 bg-white p-1 shadow-xl shadow-stone-900/10 sm:w-56 dark:border-stone-700 dark:bg-stone-900 dark:shadow-black/30"
              >
                <button
                  :for={
                    {label, modal, icon} <- [
                      {"New task", "new_task", "hero-plus"},
                      {"Columns", "columns", "hero-view-columns"},
                      {"Project notes", "notes", "hero-document-text"},
                      {"Recent activity", "activity", "hero-clock"}
                    ]
                  }
                  id={"open-#{modal}-modal"}
                  type="button"
                  class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm font-medium text-stone-700 transition hover:bg-stone-100 hover:text-stone-950 dark:text-stone-200 dark:hover:bg-stone-800 dark:hover:text-stone-50"
                  phx-click="open_modal"
                  phx-value-modal={modal}
                >
                  <.icon name={icon} class="size-4" /> {label}
                </button>
              </div>
            </div>
          </div>
        </div>

        <section class="min-w-0">
          <div
            :if={@view == :board}
            id="task-board"
            phx-hook="TaskBoard"
            class="cherry-board-scroll flex snap-x gap-3 overflow-x-auto pb-4 sm:gap-4"
          >
            <section
              :for={column <- @columns}
              id={"column-#{column.id}"}
              data-board-column
              data-column-id={column.id}
              class="flex max-h-[calc(100dvh-13rem)] min-h-[24rem] w-[min(19rem,calc(100vw-2rem))] shrink-0 snap-start flex-col rounded-xl border border-stone-200 bg-stone-100/80 p-3 shadow-sm sm:max-h-[calc(100vh-14rem)] sm:min-h-[28rem] sm:w-[19rem] dark:border-stone-700 dark:bg-stone-900/70"
            >
              <div class="mb-3 flex items-center justify-between gap-3">
                <h2 class="text-sm font-semibold text-stone-800 dark:text-stone-100">
                  {column.name}
                </h2>
                <span
                  id={"column-#{column.id}-count"}
                  class="rounded-md bg-white px-2 py-1 text-xs font-semibold text-stone-500 shadow-sm dark:bg-stone-800 dark:text-stone-300"
                >
                  {Enum.count(@tasks_by_column[column.id] || [])}
                </span>
              </div>

              <div
                id={"column-#{column.id}-tasks"}
                data-task-list
                data-column-id={column.id}
                class="min-h-40 flex-1 space-y-3 overflow-y-auto rounded-lg"
              >
                <div class="hidden rounded-lg border border-dashed border-stone-300 bg-white/60 p-4 text-center text-sm text-stone-500 only:block dark:border-stone-700 dark:bg-stone-800/50 dark:text-stone-400">
                  Drop tasks here
                </div>
                <article
                  :for={task <- @tasks_by_column[column.id] || []}
                  id={"task-#{task.id}"}
                  data-task-card
                  data-task-id={task.id}
                  class="group cursor-grab rounded-xl border border-stone-200 bg-white p-3 shadow-sm transition hover:-translate-y-0.5 hover:border-stone-300 hover:shadow-md active:cursor-grabbing dark:border-stone-700 dark:bg-stone-950 dark:hover:border-stone-600"
                >
                  <div class="flex items-start justify-between gap-2">
                    <div class="min-w-0 flex-1">
                      <h3
                        id={"task-#{task.id}-title"}
                        class="break-words text-sm font-semibold leading-5 text-stone-950 dark:text-stone-50"
                      >
                        {task.title}
                      </h3>
                    </div>
                    <span class="shrink-0 rounded-md bg-stone-100 px-1.5 py-0.5 text-[0.68rem] font-semibold uppercase text-stone-500 dark:bg-stone-800 dark:text-stone-300">
                      {task.priority}
                    </span>
                  </div>

                  <div
                    id={"task-#{task.id}-body"}
                    class="mt-2 min-h-6 line-clamp-3 text-sm leading-6 text-stone-600 dark:text-stone-300 [&_p]:text-stone-600 dark:[&_p]:text-stone-300"
                  >
                    <%= if task.body in [nil, ""] do %>
                      Double-click to view task
                    <% else %>
                      {Markdown.render(task.body)}
                    <% end %>
                  </div>

                  <div class="mt-3 flex flex-wrap items-center gap-2 text-xs text-stone-500 dark:text-stone-400">
                    <span
                      :if={task.due_date}
                      class="inline-flex items-center gap-1 rounded-md bg-amber-50 px-2 py-1 font-medium text-amber-700 dark:bg-amber-950/50 dark:text-amber-300"
                    >
                      <.icon name="hero-calendar-days" class="size-3.5" /> {task.due_date}
                    </span>
                    <span
                      :for={tag <- task.tags}
                      class={[
                        "rounded-md border px-2 py-1 font-medium",
                        tag_color_class(tag.color)
                      ]}
                    >
                      {tag.name}
                    </span>
                  </div>

                  <div class="mt-3 flex justify-end border-t border-stone-100 pt-3 dark:border-stone-800">
                    <button
                      id={"task-#{task.id}-archive"}
                      type="button"
                      data-no-drag
                      class="rounded-md p-1.5 text-stone-400 transition hover:bg-rose-50 hover:text-rose-700 dark:hover:bg-rose-950/50 dark:hover:text-rose-300"
                      phx-click="archive_task"
                      phx-value-id={task.id}
                      aria-label={"Archive #{task.title}"}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </article>
              </div>
            </section>
          </div>

          <div
            :if={@view == :list}
            id="task-list-view"
            class="overflow-x-auto rounded-xl border border-stone-200 bg-white/85 shadow-sm dark:border-stone-700 dark:bg-stone-900/85"
          >
            <table class="min-w-[42rem] w-full text-left text-sm">
              <thead class="bg-stone-100/80 text-xs font-semibold uppercase text-stone-500 dark:bg-stone-800/80 dark:text-stone-400">
                <tr>
                  <th class="p-3">Task</th>
                  <th class="p-3">Column</th>
                  <th class="p-3">Priority</th>
                  <th class="p-3">Due</th>
                  <th class="p-3">Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={task <- @tasks}
                  id={"task-row-#{task.id}"}
                  class="border-t border-stone-100 dark:border-stone-800"
                >
                  <td class="p-3 font-medium text-stone-950 dark:text-stone-50">{task.title}</td>
                  <td class="p-3 text-stone-600 dark:text-stone-300">{task.column.name}</td>
                  <td class="p-3 text-stone-600 dark:text-stone-300">{task.priority}</td>
                  <td class="p-3 text-stone-600 dark:text-stone-300">{task.due_date}</td>
                  <td class="p-3 text-stone-600 dark:text-stone-300">{task.status}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div
            :if={@view == :calendar}
            id="task-calendar-view"
            class="rounded-xl border border-stone-200 bg-white/85 p-4 shadow-sm dark:border-stone-700 dark:bg-stone-900/85"
          >
            <h2 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
              Upcoming due dates
            </h2>
            <div class="mt-4 space-y-2">
              <div class="hidden rounded-lg border border-dashed border-stone-300 p-6 text-center text-sm text-stone-500 only:block dark:border-stone-700 dark:text-stone-400">
                No due dates yet
              </div>
              <div
                :for={task <- Enum.filter(@tasks, & &1.due_date)}
                id={"task-date-#{task.id}"}
                class="flex flex-col gap-1 rounded-lg border border-stone-100 bg-stone-50/80 p-3 sm:flex-row sm:items-center sm:justify-between dark:border-stone-800 dark:bg-stone-950/80"
              >
                <span class="break-words font-medium text-stone-900 dark:text-stone-50">
                  {task.title}
                </span>
                <span class="text-sm text-stone-500 dark:text-stone-400">{task.due_date}</span>
              </div>
            </div>
          </div>
        </section>

        <div
          :if={@active_modal}
          id="project-modal-backdrop"
          class="fixed inset-0 z-50 grid place-items-end overflow-y-auto px-2 py-2 sm:place-items-center sm:px-4 sm:py-8"
        >
          <button
            type="button"
            class="absolute inset-0 bg-stone-950/40 backdrop-blur-sm dark:bg-black/65"
            phx-click="close_modal"
            aria-label="Close modal"
          >
          </button>
          <section
            id="project-modal"
            class="relative max-h-[calc(100dvh-1rem)] w-full max-w-4xl overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-2xl shadow-stone-950/20 sm:max-h-[88vh] dark:border-stone-700 dark:bg-stone-900 dark:shadow-black/50"
          >
            <div class="border-b border-stone-100 bg-stone-50/80 px-4 py-4 sm:px-6 sm:py-5 dark:border-stone-800 dark:bg-stone-950/70">
              <div class="flex items-start justify-between gap-4">
                <div class="flex min-w-0 gap-3 sm:gap-4">
                  <span class="hidden size-11 shrink-0 place-items-center rounded-xl bg-rose-50 text-rose-700 ring-1 ring-rose-100 sm:grid dark:bg-rose-950/40 dark:text-rose-300 dark:ring-rose-900/60">
                    <.icon
                      name={
                        case @active_modal do
                          :new_task -> "hero-plus"
                          :view_task -> "hero-document-magnifying-glass"
                          :edit_task -> "hero-pencil-square"
                          :columns -> "hero-view-columns"
                          :notes -> "hero-document-text"
                          :activity -> "hero-clock"
                        end
                      }
                      class="size-5"
                    />
                  </span>
                  <div class="min-w-0">
                    <p class="text-xs font-semibold uppercase text-rose-700 dark:text-rose-300">
                      Project tools
                    </p>
                    <h2 class="mt-1 break-words text-lg font-semibold text-stone-950 sm:text-xl dark:text-stone-50">
                      <%= case @active_modal do %>
                        <% :new_task -> %>
                          New task
                        <% :view_task -> %>
                          Task details
                        <% :edit_task -> %>
                          Edit task
                        <% :columns -> %>
                          Columns
                        <% :notes -> %>
                          Project notes
                        <% :activity -> %>
                          Recent activity
                      <% end %>
                    </h2>
                    <p class="mt-1 hidden max-w-2xl text-sm leading-6 text-stone-500 sm:block dark:text-stone-400">
                      <%= case @active_modal do %>
                        <% :new_task -> %>
                          Capture the work, place it on the board, and add the context needed to move it forward.
                        <% :view_task -> %>
                          Review the complete task content before deciding what needs to change.
                        <% :edit_task -> %>
                          Update the task details, board placement, priority, due date, and tags in one place.
                        <% :columns -> %>
                          Rename, add, or remove the lanes that shape this board.
                        <% :notes -> %>
                          Keep the project context close while the board stays clean.
                        <% :activity -> %>
                          Review recent changes and movement on this workspace.
                      <% end %>
                    </p>
                  </div>
                </div>
                <button
                  id="close-project-modal"
                  type="button"
                  class="rounded-lg p-2 text-stone-400 transition hover:bg-stone-100 hover:text-stone-900 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                  aria-label="Close modal"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
            </div>

            <div
              :if={@active_modal == :new_task}
              id="new-task-modal"
              class="max-h-[calc(100dvh-8rem)] overflow-y-auto sm:max-h-[calc(88vh-8.5rem)]"
            >
              <.form
                id="task-form"
                for={@task_form}
                phx-submit="create_task"
                phx-hook="TaskForm"
                class="cherry-form"
              >
                <div class="grid min-w-0 gap-0 lg:grid-cols-[minmax(0,1fr)_20rem]">
                  <div class="space-y-5 p-4 sm:p-6">
                    <.input
                      field={@task_form[:title]}
                      label="Task title"
                      class="cherry-field"
                      required
                    />
                    <.input
                      field={@task_form[:body]}
                      type="textarea"
                      label="Notes"
                      rows="7"
                      class="cherry-field cherry-notes-field"
                    />
                  </div>
                  <aside class="space-y-4 border-t border-stone-100 bg-stone-50/70 p-4 sm:p-6 dark:border-stone-800 dark:bg-stone-950/40 lg:border-l lg:border-t-0">
                    <div>
                      <h3 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
                        Board details
                      </h3>
                      <p class="mt-1 text-xs leading-5 text-stone-500 dark:text-stone-400">
                        These settings decide where the task lands and how urgent it feels.
                      </p>
                    </div>
                    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-1">
                      <.input
                        field={@task_form[:column_id]}
                        type="select"
                        label="Column"
                        class="cherry-field"
                        options={Enum.map(@columns, &{&1.name, &1.id})}
                      />
                      <.input
                        field={@task_form[:priority]}
                        type="select"
                        label="Priority"
                        class="cherry-field"
                        options={[Low: "low", Normal: "normal", High: "high", Urgent: "urgent"]}
                      />
                      <.input
                        field={@task_form[:due_date]}
                        type="date"
                        label="Due date"
                        class="cherry-field"
                      />
                      <.tag_input form={@task_form} id="task-tags-editor" label="Tags" />
                    </div>
                  </aside>
                </div>
                <div class="flex flex-col-reverse gap-2 border-t border-stone-100 bg-white px-4 py-4 sm:flex-row sm:items-center sm:justify-end sm:px-6 dark:border-stone-800 dark:bg-stone-900">
                  <button
                    type="button"
                    class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                    phx-click="close_modal"
                  >
                    Cancel
                  </button>
                  <button
                    id="create-task-button"
                    class="w-full rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                    type="submit"
                  >
                    Create task
                  </button>
                </div>
              </.form>
            </div>

            <div
              :if={@active_modal == :view_task}
              id="view-task-modal"
              class="max-h-[calc(100dvh-8rem)] overflow-y-auto sm:max-h-[calc(88vh-8.5rem)]"
            >
              <div :if={@viewing_task} class="grid min-w-0 gap-0 lg:grid-cols-[minmax(0,1fr)_20rem]">
                <div class="space-y-5 p-4 sm:p-6">
                  <div>
                    <p class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                      Task
                    </p>
                    <h3
                      id={"view-task-#{@viewing_task.id}-title"}
                      class="mt-1 break-words text-xl font-semibold tracking-normal text-stone-950 sm:text-2xl dark:text-stone-50"
                    >
                      {@viewing_task.title}
                    </h3>
                  </div>

                  <div
                    id={"view-task-#{@viewing_task.id}-body"}
                    class="min-h-48 max-w-none rounded-xl border border-stone-200 bg-stone-50/80 p-4 text-sm leading-6 text-stone-700 dark:border-stone-800 dark:bg-stone-950/60 dark:text-stone-300 [&_code]:dark:bg-stone-800 [&_h1]:mb-2 [&_h1]:text-lg [&_h1]:font-semibold [&_h1]:text-stone-950 dark:[&_h1]:text-stone-50 [&_h2]:mb-2 [&_h2]:font-semibold [&_h2]:text-stone-950 dark:[&_h2]:text-stone-50 [&_h3]:mb-2 [&_h3]:font-semibold [&_h3]:text-stone-950 dark:[&_h3]:text-stone-50 [&_p]:mb-3 [&_p]:text-stone-700 dark:[&_p]:text-stone-300 [&_strong]:font-semibold [&_strong]:text-stone-900 dark:[&_strong]:text-stone-100"
                  >
                    <%= if @viewing_task.body in [nil, ""] do %>
                      <p class="text-sm text-stone-500 dark:text-stone-400">No notes yet.</p>
                    <% else %>
                      {Markdown.render(@viewing_task.body)}
                    <% end %>
                  </div>
                </div>

                <aside class="space-y-4 border-t border-stone-100 bg-stone-50/70 p-4 sm:p-6 dark:border-stone-800 dark:bg-stone-950/40 lg:border-l lg:border-t-0">
                  <div>
                    <h3 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
                      Task settings
                    </h3>
                    <p class="mt-1 text-xs leading-5 text-stone-500 dark:text-stone-400">
                      Current board placement and scheduling details.
                    </p>
                  </div>

                  <dl id="view-task-meta" class="space-y-3 text-sm">
                    <div class="rounded-lg border border-stone-200 bg-white/80 p-3 dark:border-stone-800 dark:bg-stone-900/80">
                      <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                        Column
                      </dt>
                      <dd class="mt-1 font-medium text-stone-950 dark:text-stone-50">
                        {@viewing_task.column.name}
                      </dd>
                    </div>
                    <div class="rounded-lg border border-stone-200 bg-white/80 p-3 dark:border-stone-800 dark:bg-stone-900/80">
                      <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                        Priority
                      </dt>
                      <dd class="mt-1 font-medium capitalize text-stone-950 dark:text-stone-50">
                        {@viewing_task.priority}
                      </dd>
                    </div>
                    <div class="rounded-lg border border-stone-200 bg-white/80 p-3 dark:border-stone-800 dark:bg-stone-900/80">
                      <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                        Status
                      </dt>
                      <dd class="mt-1 font-medium capitalize text-stone-950 dark:text-stone-50">
                        {String.replace(@viewing_task.status, "_", " ")}
                      </dd>
                    </div>
                    <div class="rounded-lg border border-stone-200 bg-white/80 p-3 dark:border-stone-800 dark:bg-stone-900/80">
                      <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                        Due date
                      </dt>
                      <dd class="mt-1 font-medium text-stone-950 dark:text-stone-50">
                        {@viewing_task.due_date || "None"}
                      </dd>
                    </div>
                  </dl>

                  <div :if={@viewing_task.tags != []} id="view-task-tags" class="flex flex-wrap gap-2">
                    <span
                      :for={tag <- @viewing_task.tags}
                      class={[
                        "rounded-md border px-2 py-1 text-xs font-medium",
                        tag_color_class(tag.color)
                      ]}
                    >
                      {tag.name}
                    </span>
                  </div>
                </aside>
              </div>

              <div class="flex flex-col-reverse gap-2 border-t border-stone-100 bg-white px-4 py-4 sm:flex-row sm:items-center sm:justify-end sm:px-6 dark:border-stone-800 dark:bg-stone-900">
                <button
                  type="button"
                  class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                >
                  Close
                </button>
                <button
                  id="edit-viewed-task-button"
                  type="button"
                  class="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                  phx-click="edit_task"
                  phx-value-task_id={@viewing_task && @viewing_task.id}
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Edit
                </button>
              </div>
            </div>

            <div
              :if={@active_modal == :edit_task}
              id="edit-task-modal"
              class="max-h-[calc(100dvh-8rem)] overflow-y-auto sm:max-h-[calc(88vh-8.5rem)]"
            >
              <.form
                :if={@edit_task_form}
                id="edit-task-form"
                for={@edit_task_form}
                phx-submit="update_task"
                class="cherry-form"
              >
                <div class="grid min-w-0 gap-0 lg:grid-cols-[minmax(0,1fr)_20rem]">
                  <div class="space-y-5 p-4 sm:p-6">
                    <.input field={@edit_task_form[:id]} type="hidden" />
                    <.input
                      field={@edit_task_form[:title]}
                      label="Task title"
                      class="cherry-field"
                      required
                    />
                    <.input
                      field={@edit_task_form[:body]}
                      type="textarea"
                      label="Notes"
                      rows="8"
                      class="cherry-field cherry-notes-field"
                    />
                  </div>
                  <aside class="space-y-4 border-t border-stone-100 bg-stone-50/70 p-4 sm:p-6 dark:border-stone-800 dark:bg-stone-950/40 lg:border-l lg:border-t-0">
                    <div>
                      <h3 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
                        Task settings
                      </h3>
                      <p class="mt-1 text-xs leading-5 text-stone-500 dark:text-stone-400">
                        Keep the card organized without returning to the board.
                      </p>
                    </div>
                    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-1">
                      <.input
                        field={@edit_task_form[:column_id]}
                        type="select"
                        label="Column"
                        class="cherry-field"
                        options={Enum.map(@columns, &{&1.name, &1.id})}
                      />
                      <.input
                        field={@edit_task_form[:priority]}
                        type="select"
                        label="Priority"
                        class="cherry-field"
                        options={[Low: "low", Normal: "normal", High: "high", Urgent: "urgent"]}
                      />
                      <.input
                        field={@edit_task_form[:status]}
                        type="select"
                        label="Status"
                        class="cherry-field"
                        options={[Open: "open", "In progress": "in_progress", Done: "done"]}
                      />
                      <.input
                        field={@edit_task_form[:due_date]}
                        type="date"
                        label="Due date"
                        class="cherry-field"
                      />
                      <.tag_input form={@edit_task_form} id="edit-task-tags-editor" label="Tags" />
                    </div>
                  </aside>
                </div>
                <div class="flex flex-col-reverse gap-2 border-t border-stone-100 bg-white px-4 py-4 sm:flex-row sm:items-center sm:justify-end sm:px-6 dark:border-stone-800 dark:bg-stone-900">
                  <button
                    type="button"
                    class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                    phx-click="close_modal"
                  >
                    Cancel
                  </button>
                  <button
                    id="update-task-button"
                    class="w-full rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                    type="submit"
                  >
                    Save changes
                  </button>
                </div>
              </.form>
            </div>

            <div
              :if={@active_modal == :columns}
              id="columns-modal"
              class="max-h-[calc(100dvh-8rem)] overflow-y-auto sm:max-h-[calc(88vh-8.5rem)]"
            >
              <div class="grid min-w-0 gap-0 lg:grid-cols-[minmax(0,1fr)_20rem]">
                <div class="space-y-3 p-4 sm:p-6">
                  <div>
                    <h3 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
                      Board columns
                    </h3>
                    <p class="mt-1 text-xs leading-5 text-stone-500 dark:text-stone-400">
                      Tasks are kept when a column is removed and moved into the first remaining column.
                    </p>
                  </div>

                  <div id="column-management-list" class="space-y-2">
                    <div
                      :for={column <- @columns}
                      id={"column-manager-#{column.id}"}
                      class="rounded-xl border border-stone-200 bg-white p-3 shadow-sm dark:border-stone-700 dark:bg-stone-950"
                    >
                      <.form
                        :if={@editing_column_id == column.id}
                        id={"edit-column-form-#{column.id}"}
                        for={@edit_column_form}
                        phx-submit="update_column"
                        class="cherry-form"
                      >
                        <.input field={@edit_column_form[:id]} type="hidden" />
                        <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
                          <.input
                            field={@edit_column_form[:name]}
                            id={"column-name-#{column.id}"}
                            label="Column name"
                            class="cherry-field"
                            required
                          />
                          <div class="flex gap-2">
                            <button
                              type="button"
                              class="rounded-lg px-3 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                              phx-click="cancel_column_edit"
                            >
                              Cancel
                            </button>
                            <button
                              id={"save-column-#{column.id}"}
                              type="submit"
                              class="rounded-lg bg-stone-950 px-3 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                            >
                              Save
                            </button>
                          </div>
                        </div>
                      </.form>

                      <div
                        :if={@editing_column_id != column.id}
                        class="flex items-center justify-between gap-3"
                      >
                        <div class="min-w-0">
                          <p class="truncate text-sm font-semibold text-stone-950 dark:text-stone-50">
                            {column.name}
                          </p>
                          <p class="mt-1 text-xs text-stone-500 dark:text-stone-400">
                            {Enum.count(@tasks_by_column[column.id] || [])} tasks
                          </p>
                        </div>
                        <div class="flex shrink-0 items-center gap-1">
                          <button
                            id={"edit-column-#{column.id}"}
                            type="button"
                            class="rounded-lg p-2 text-stone-400 transition hover:bg-stone-100 hover:text-stone-900 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                            phx-click="edit_column"
                            phx-value-id={column.id}
                            aria-label={"Rename #{column.name}"}
                          >
                            <.icon name="hero-pencil-square" class="size-4" />
                          </button>
                          <button
                            id={"delete-column-#{column.id}"}
                            type="button"
                            class="rounded-lg p-2 text-stone-400 transition hover:bg-rose-50 hover:text-rose-700 disabled:cursor-not-allowed disabled:opacity-40 dark:hover:bg-rose-950/50 dark:hover:text-rose-300"
                            phx-click="delete_column"
                            phx-value-id={column.id}
                            disabled={Enum.count(@columns) == 1}
                            aria-label={"Delete #{column.name}"}
                          >
                            <.icon name="hero-trash" class="size-4" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <aside class="space-y-4 border-t border-stone-100 bg-stone-50/70 p-4 sm:p-6 dark:border-stone-800 dark:bg-stone-950/40 lg:border-l lg:border-t-0">
                  <div>
                    <h3 class="text-sm font-semibold text-stone-950 dark:text-stone-50">
                      Add a column
                    </h3>
                    <p class="mt-1 text-xs leading-5 text-stone-500 dark:text-stone-400">
                      New columns are added to the right side of the board.
                    </p>
                  </div>
                  <.form
                    id="column-form"
                    for={@column_form}
                    phx-submit="create_column"
                    class="cherry-form space-y-4"
                  >
                    <.input
                      field={@column_form[:name]}
                      id="new-column-name"
                      label="Column name"
                      placeholder="Blocked"
                      class="cherry-field"
                      required
                    />
                    <button
                      id="create-column-button"
                      type="submit"
                      class="w-full rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                    >
                      Add column
                    </button>
                  </.form>
                </aside>
              </div>
            </div>

            <div
              :if={@active_modal == :notes}
              class="max-h-[calc(100dvh-8rem)] overflow-y-auto p-4 sm:p-5"
            >
              <div
                id="project-notes"
                class="max-w-none rounded-xl border border-stone-200 bg-stone-50/80 p-4 text-sm leading-6 text-stone-600 dark:border-stone-800 dark:bg-stone-950/60 dark:text-stone-300 [&_h1]:mb-2 [&_h1]:text-lg [&_h1]:font-semibold [&_h1]:text-stone-950 dark:[&_h1]:text-stone-50 [&_h2]:mb-2 [&_h2]:font-semibold [&_h2]:text-stone-950 dark:[&_h2]:text-stone-50 [&_p]:mb-3 [&_strong]:font-semibold [&_strong]:text-stone-900 dark:[&_strong]:text-stone-100"
              >
                {Markdown.render(@project.description)}
              </div>
            </div>

            <div
              :if={@active_modal == :activity}
              id="recent-activity"
              class="max-h-[calc(100dvh-8rem)] space-y-2 overflow-y-auto p-4 sm:p-5"
            >
              <p
                :for={event <- @activity}
                class="rounded-lg bg-stone-50 p-2 text-xs text-stone-600 dark:bg-stone-950 dark:text-stone-300"
              >
                <span class="font-semibold text-stone-800 dark:text-stone-100">{event.actor}</span>
                {event.action} {event.entity_type} #{event.entity_id}
              </p>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
