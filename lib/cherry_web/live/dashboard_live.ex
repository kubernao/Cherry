defmodule CherryWeb.DashboardLive do
  use CherryWeb, :live_view

  alias Cherry.Workspace
  alias CherryWeb.Markdown

  @deleted_retention_days 5

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:query, "")
     |> assign(:active_modal, nil)
     |> assign(:editing_project, nil)
     |> assign(:deleting_project, nil)
     |> assign(:project_form, project_form())
     |> load_projects()}
  end

  def handle_event("create_project", %{"project" => attrs}, socket) do
    case Workspace.create_project(attrs, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created.")
         |> assign(:active_modal, nil)
         |> push_navigate(to: ~p"/projects/#{project.id}")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           active_modal: :new_project,
           project_form: to_form(changeset, as: :project)
         )}
    end
  end

  def handle_event("edit_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id)

    {:noreply,
     assign(socket,
       active_modal: :edit_project,
       editing_project: project,
       deleting_project: nil,
       project_form: project_form(project)
     )}
  end

  def handle_event("update_project", %{"project" => attrs}, socket) do
    project = socket.assigns.editing_project || Workspace.get_project!(attrs["id"])

    case Workspace.update_project(project, attrs,
           actor: "web",
           user_id: socket.assigns.current_user.id
         ) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project updated.")
         |> close_project_modal()
         |> load_projects()}

      {:error, changeset} ->
        {:noreply, assign(socket, project_form: to_form(changeset, as: :project))}
    end
  end

  def handle_event("archive_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id)

    case Workspace.archive_project(project, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project archived.")
         |> close_project_modal()
         |> load_projects()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Project could not be archived.")}
    end
  end

  def handle_event("restore_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id)

    case Workspace.restore_project(project, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project restored.")
         |> close_project_modal()
         |> load_projects()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Project could not be restored.")}
    end
  end

  def handle_event("restore_deleted_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id, include_deleted: true)

    case Workspace.restore_project(project, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project restored.")
         |> close_project_modal()
         |> load_projects()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Project could not be restored.")}
    end
  end

  def handle_event("restore_deleted_task", %{"id" => id}, socket) do
    task = Workspace.get_task!(id, include_deleted: true)

    case Workspace.restore_task(task, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Card restored.")
         |> close_project_modal()
         |> load_projects()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Card could not be restored.")}
    end
  end

  def handle_event("confirm_delete_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id)

    {:noreply,
     assign(socket,
       active_modal: :delete_project,
       editing_project: nil,
       deleting_project: project
     )}
  end

  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Workspace.get_project!(id)

    case Workspace.delete_project(project, actor: "web", user_id: socket.assigns.current_user.id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project deleted.")
         |> close_project_modal()
         |> load_projects()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Project could not be deleted.")}
    end
  end

  def handle_event("open_modal", %{"modal" => "new_project"}, socket) do
    {:noreply,
     assign(socket,
       active_modal: :new_project,
       editing_project: nil,
       deleting_project: nil,
       project_form: project_form()
     )}
  end

  def handle_event("open_modal", %{"modal" => "restore_deleted"}, socket) do
    {:noreply,
     assign(socket,
       active_modal: :restore_deleted,
       editing_project: nil,
       deleting_project: nil
     )}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, close_project_modal(socket)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    results = if String.trim(query) == "", do: nil, else: Workspace.search(query)
    {:noreply, assign(socket, query: query, search_results: results)}
  end

  defp load_projects(socket) do
    recently_deleted = Workspace.list_recently_deleted()

    socket
    |> assign(:projects, Workspace.list_projects())
    |> assign(:archived_projects, Workspace.list_projects(archived: true))
    |> assign(:recently_deleted, recently_deleted)
    |> assign(:recently_deleted_count, recovery_count(recently_deleted))
    |> assign(:search_results, nil)
  end

  defp close_project_modal(socket) do
    assign(socket,
      active_modal: nil,
      editing_project: nil,
      deleting_project: nil,
      project_form: project_form()
    )
  end

  defp recovery_count(%{projects: projects, tasks: tasks}),
    do: Enum.count(projects) + Enum.count(tasks)

  defp recovery_empty?(%{projects: [], tasks: []}), do: true
  defp recovery_empty?(_recently_deleted), do: false

  defp expires_on(%{deleted_at: deleted_at}) do
    deleted_at
    |> DateTime.add(@deleted_retention_days, :day)
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp project_form(project \\ nil)

  defp project_form(nil) do
    to_form(
      %{"title" => "", "description" => "", "status" => "active", "priority" => "normal"},
      as: :project
    )
  end

  defp project_form(project) do
    to_form(
      %{
        "id" => project.id,
        "title" => project.title,
        "description" => project.description || "",
        "status" => project.status,
        "priority" => project.priority
      },
      as: :project
    )
  end

  defp status_options, do: [{"Active", "active"}, {"Paused", "paused"}, {"Done", "done"}]

  defp priority_options,
    do: [{"Low", "low"}, {"Normal", "normal"}, {"High", "high"}, {"Urgent", "urgent"}]

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section
        class="min-w-0 space-y-5 sm:space-y-6"
        phx-window-keydown="close_modal"
        phx-key="escape"
      >
        <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div class="min-w-0">
            <p class="text-sm font-semibold text-rose-700 dark:text-rose-300">Workspace</p>
            <h1 class="mt-1 break-words text-2xl font-semibold tracking-normal text-stone-950 sm:text-3xl dark:text-stone-50">
              Projects
            </h1>
            <p class="mt-2 max-w-xl text-sm leading-6 text-stone-600 dark:text-stone-300">
              Plan work, move tasks, and keep project notes close.
            </p>
          </div>
          <div class="flex w-full flex-col gap-3 md:w-auto md:flex-row md:items-center">
            <form id="project-search-form" phx-change="search" class="relative w-full md:w-96">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-3 top-3 size-5 text-stone-400"
              />
              <input
                id="project-search"
                name="q"
                value={@query}
                placeholder="Search projects and tasks"
                class="cherry-field cherry-search-field"
              />
            </form>
            <button
              id="new-project-button"
              type="button"
              class="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-stone-950 px-4 py-2.5 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
              phx-click="open_modal"
              phx-value-modal="new_project"
            >
              <.icon name="hero-plus" class="size-4" />
              <span>New project</span>
            </button>
          </div>
        </div>

        <div
          :if={@search_results}
          id="search-results"
          class="rounded-xl border border-stone-200 bg-white/85 p-4 shadow-sm dark:border-stone-700 dark:bg-stone-900/85"
        >
          <h2 class="text-sm font-semibold text-stone-800 dark:text-stone-100">Search results</h2>
          <div class="mt-3 grid gap-3 md:grid-cols-2">
            <.link
              :for={project <- @search_results.projects}
              navigate={~p"/projects/#{project.id}"}
              class="block rounded-lg border border-stone-200 bg-stone-50/80 p-3 transition hover:-translate-y-0.5 hover:border-stone-300 hover:bg-white dark:border-stone-700 dark:bg-stone-950/70 dark:hover:border-stone-600 dark:hover:bg-stone-950"
            >
              <p class="font-medium text-stone-950 dark:text-stone-50">{project.title}</p>
              <p class="text-xs text-stone-500 dark:text-stone-400">Project · {project.status}</p>
            </.link>
            <.link
              :for={task <- @search_results.tasks}
              navigate={~p"/projects/#{task.project_id}"}
              class="block rounded-lg border border-stone-200 bg-stone-50/80 p-3 transition hover:-translate-y-0.5 hover:border-stone-300 hover:bg-white dark:border-stone-700 dark:bg-stone-950/70 dark:hover:border-stone-600 dark:hover:bg-stone-950"
            >
              <p class="font-medium text-stone-950 dark:text-stone-50">{task.title}</p>
              <p class="text-xs text-stone-500 dark:text-stone-400">
                Task · {task.project && task.project.title}
              </p>
            </.link>
          </div>
        </div>

        <div>
          <section>
            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <article
                :for={project <- @projects}
                id={"project-card-#{project.id}"}
                class="group rounded-xl border border-stone-200 bg-white/85 shadow-sm transition hover:-translate-y-1 hover:border-stone-300 hover:bg-white hover:shadow-md dark:border-stone-700 dark:bg-stone-900/85 dark:hover:border-stone-600 dark:hover:bg-stone-900"
              >
                <.link
                  navigate={~p"/projects/#{project.id}"}
                  id={"open-project-#{project.id}"}
                  class="block p-4 pb-2"
                >
                  <div class="flex items-start justify-between gap-3">
                    <h2 class="min-w-0 font-semibold text-stone-950 transition group-hover:text-rose-700 dark:text-stone-50 dark:group-hover:text-rose-300">
                      {project.title}
                    </h2>
                    <span class="rounded-md bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700 dark:bg-rose-950/50 dark:text-rose-300">
                      {project.priority}
                    </span>
                  </div>
                  <p class="mt-3 text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                    {project.status}
                  </p>
                </.link>
                <div
                  id={"project-card-#{project.id}-body"}
                  class="line-clamp-3 min-h-12 px-4 pb-4 text-sm leading-6 text-stone-600 dark:text-stone-300 [&_p]:text-stone-600 dark:[&_p]:text-stone-300"
                >
                  {Markdown.render(project.description)}
                </div>
                <div class="flex items-center justify-between gap-2 border-t border-stone-100 px-4 py-3 dark:border-stone-800">
                  <button
                    id={"edit-project-#{project.id}"}
                    type="button"
                    class="rounded-md p-1.5 text-stone-400 transition hover:bg-stone-100 hover:text-stone-900 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                    phx-click="edit_project"
                    phx-value-id={project.id}
                    aria-label={"Edit #{project.title}"}
                  >
                    <.icon name="hero-pencil-square" class="size-4" />
                  </button>
                  <button
                    id={"delete-project-#{project.id}"}
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-md border border-rose-200 px-2.5 py-1.5 text-xs font-semibold text-rose-700 transition hover:border-rose-300 hover:bg-rose-50 dark:border-rose-900/70 dark:text-rose-300 dark:hover:border-rose-800 dark:hover:bg-rose-950/50"
                    phx-click="confirm_delete_project"
                    phx-value-id={project.id}
                    aria-label={"Delete #{project.title}"}
                  >
                    <.icon name="hero-trash" class="size-4" />
                    <span>Delete</span>
                  </button>
                </div>
              </article>

              <button
                id="recently-deleted-card"
                type="button"
                class="group flex min-h-40 flex-col justify-between rounded-xl border border-dashed border-stone-300 bg-white/65 p-4 text-left shadow-sm transition hover:-translate-y-1 hover:border-emerald-300 hover:bg-white hover:shadow-md focus:outline-none focus:ring-2 focus:ring-emerald-300 md:col-start-2 xl:col-start-3 dark:border-stone-700 dark:bg-stone-900/65 dark:hover:border-emerald-800 dark:hover:bg-stone-900"
                phx-click="open_modal"
                phx-value-modal="restore_deleted"
              >
                <span class="flex items-start justify-between gap-3">
                  <span>
                    <span class="block font-semibold text-stone-950 transition group-hover:text-emerald-700 dark:text-stone-50 dark:group-hover:text-emerald-300">
                      Recently deleted
                    </span>
                    <span class="mt-3 block text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                      Restore window
                    </span>
                  </span>
                  <span class="grid size-9 shrink-0 place-items-center rounded-lg bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100 transition group-hover:scale-105 dark:bg-emerald-950/40 dark:text-emerald-300 dark:ring-emerald-900/60">
                    <.icon name="hero-arrow-path-rounded-square" class="size-4" />
                  </span>
                </span>
                <span class="mt-4 block text-sm leading-6 text-stone-500 dark:text-stone-400">
                  Restore projects and cards deleted in the last 5 days.
                </span>
                <span class="mt-4 inline-flex w-fit items-center rounded-md bg-stone-100 px-2.5 py-1 text-xs font-semibold text-stone-600 dark:bg-stone-800 dark:text-stone-300">
                  {@recently_deleted_count} recoverable
                </span>
              </button>
            </div>

            <div
              :if={@projects == []}
              id="empty-projects"
              class="rounded-xl border border-dashed border-stone-300 bg-white/70 p-8 text-center dark:border-stone-700 dark:bg-stone-900/70"
            >
              <p class="font-medium text-stone-950 dark:text-stone-50">No projects yet</p>
              <p class="mt-1 text-sm text-stone-500 dark:text-stone-400">
                Create one to get the board, list, notes, and CLI API moving.
              </p>
            </div>
          </section>
        </div>

        <section
          :if={@archived_projects != []}
          id="archived-projects"
          class="rounded-xl border border-stone-200 bg-white/75 p-4 shadow-sm dark:border-stone-700 dark:bg-stone-900/75"
        >
          <h2 class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
            Archived
          </h2>
          <div class="mt-3 flex flex-wrap gap-2">
            <div
              :for={project <- @archived_projects}
              id={"archived-project-#{project.id}"}
              class="flex items-center gap-2 rounded-lg border border-stone-200 bg-white px-3 py-2 text-sm text-stone-600 transition hover:-translate-y-0.5 hover:border-stone-300 dark:border-stone-700 dark:bg-stone-950 dark:text-stone-300 dark:hover:border-stone-600"
            >
              <.link
                navigate={~p"/projects/#{project.id}"}
                class="font-medium transition hover:text-stone-950 dark:hover:text-stone-50"
              >
                {project.title}
              </.link>
              <button
                id={"restore-project-#{project.id}"}
                type="button"
                class="rounded-md p-1 text-stone-400 transition hover:bg-emerald-50 hover:text-emerald-700 dark:hover:bg-emerald-950/50 dark:hover:text-emerald-300"
                phx-click="restore_project"
                phx-value-id={project.id}
                aria-label={"Restore #{project.title}"}
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" />
              </button>
              <button
                id={"delete-archived-project-#{project.id}"}
                type="button"
                class="rounded-md p-1 text-stone-400 transition hover:bg-rose-50 hover:text-rose-700 dark:hover:bg-rose-950/50 dark:hover:text-rose-300"
                phx-click="confirm_delete_project"
                phx-value-id={project.id}
                aria-label={"Delete #{project.title}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        </section>

        <div
          :if={@active_modal in [:new_project, :edit_project, :delete_project, :restore_deleted]}
          id="dashboard-modal-backdrop"
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
            id="dashboard-modal"
            class="relative max-h-[calc(100dvh-1rem)] w-full max-w-2xl overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-2xl shadow-stone-950/20 dark:border-stone-700 dark:bg-stone-900 dark:shadow-black/50"
          >
            <div class="border-b border-stone-100 bg-stone-50/80 px-4 py-4 sm:px-6 sm:py-5 dark:border-stone-800 dark:bg-stone-950/70">
              <div class="flex items-start justify-between gap-4">
                <div class="flex min-w-0 gap-3 sm:gap-4">
                  <span class="hidden size-11 shrink-0 place-items-center rounded-xl bg-rose-50 text-rose-700 ring-1 ring-rose-100 sm:grid dark:bg-rose-950/40 dark:text-rose-300 dark:ring-rose-900/60">
                    <.icon
                      name={
                        case @active_modal do
                          :new_project -> "hero-folder-plus"
                          :edit_project -> "hero-pencil-square"
                          :delete_project -> "hero-trash"
                          :restore_deleted -> "hero-arrow-path-rounded-square"
                        end
                      }
                      class="size-5"
                    />
                  </span>
                  <div class="min-w-0">
                    <p class="text-xs font-semibold uppercase text-rose-700 dark:text-rose-300">
                      Project
                    </p>
                    <h2 class="mt-1 break-words text-lg font-semibold text-stone-950 sm:text-xl dark:text-stone-50">
                      <%= case @active_modal do %>
                        <% :new_project -> %>
                          Create a new project
                        <% :edit_project -> %>
                          Edit project
                        <% :delete_project -> %>
                          Delete project
                        <% :restore_deleted -> %>
                          Recently deleted
                      <% end %>
                    </h2>
                    <p class="mt-1 max-w-lg text-sm leading-6 text-stone-500 dark:text-stone-400">
                      <%= case @active_modal do %>
                        <% :new_project -> %>
                          Give it a clear name and a short note so the board opens with useful context.
                        <% :edit_project -> %>
                          Update the project name, notes, status, and priority.
                        <% :delete_project -> %>
                          Move this project to Recently deleted. It will be permanently removed after 5 days.
                        <% :restore_deleted -> %>
                          Restore projects and cards before they are permanently removed.
                      <% end %>
                    </p>
                  </div>
                </div>
                <button
                  id="close-dashboard-modal"
                  type="button"
                  class="rounded-lg p-2 text-stone-400 transition hover:bg-stone-100 hover:text-stone-900 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                  aria-label="Close modal"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
            </div>

            <.form
              :if={@active_modal == :new_project}
              id="project-form"
              for={@project_form}
              phx-submit="create_project"
              class="cherry-form"
            >
              <div class="max-h-[calc(100dvh-12rem)] space-y-5 overflow-y-auto p-4 sm:p-6">
                <.input
                  field={@project_form[:title]}
                  label="Project title"
                  class="cherry-field"
                  required
                />
                <.input
                  field={@project_form[:description]}
                  type="textarea"
                  label="Description"
                  rows="7"
                  class="cherry-field cherry-notes-field"
                />
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@project_form[:status]}
                    type="select"
                    label="Status"
                    options={status_options()}
                    class="cherry-field"
                  />
                  <.input
                    field={@project_form[:priority]}
                    type="select"
                    label="Priority"
                    options={priority_options()}
                    class="cherry-field"
                  />
                </div>
              </div>
              <div class="flex flex-col-reverse gap-2 border-t border-stone-100 bg-stone-50/60 px-4 py-4 sm:flex-row sm:items-center sm:justify-end sm:px-6 dark:border-stone-800 dark:bg-stone-950/40">
                <button
                  type="button"
                  class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                >
                  Cancel
                </button>
                <button
                  id="create-project-button"
                  class="w-full rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                  type="submit"
                >
                  Create project
                </button>
              </div>
            </.form>

            <.form
              :if={@active_modal == :edit_project}
              id="edit-project-form"
              for={@project_form}
              phx-submit="update_project"
              class="cherry-form"
            >
              <input type="hidden" name="project[id]" value={@project_form[:id].value} />
              <div class="max-h-[calc(100dvh-12rem)] space-y-5 overflow-y-auto p-4 sm:p-6">
                <.input
                  field={@project_form[:title]}
                  label="Project title"
                  class="cherry-field"
                  required
                />
                <.input
                  field={@project_form[:description]}
                  type="textarea"
                  label="Description"
                  rows="7"
                  class="cherry-field cherry-notes-field"
                />
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@project_form[:status]}
                    type="select"
                    label="Status"
                    options={status_options()}
                    class="cherry-field"
                  />
                  <.input
                    field={@project_form[:priority]}
                    type="select"
                    label="Priority"
                    options={priority_options()}
                    class="cherry-field"
                  />
                </div>
              </div>
              <div class="flex flex-col gap-2 border-t border-stone-100 bg-stone-50/60 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6 dark:border-stone-800 dark:bg-stone-950/40">
                <button
                  id={"archive-edit-project-#{@editing_project.id}"}
                  type="button"
                  class="inline-flex w-full items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-amber-700 transition hover:bg-amber-50 sm:w-auto dark:text-amber-300 dark:hover:bg-amber-950/50"
                  phx-click="archive_project"
                  phx-value-id={@editing_project.id}
                >
                  <.icon name="hero-archive-box" class="size-4" /> Archive
                </button>
                <div class="flex w-full flex-col-reverse gap-2 sm:w-auto sm:flex-row sm:items-center">
                  <button
                    type="button"
                    class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                    phx-click="close_modal"
                  >
                    Cancel
                  </button>
                  <button
                    id="update-project-button"
                    class="w-full rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                    type="submit"
                  >
                    Save project
                  </button>
                </div>
              </div>
            </.form>

            <div :if={@active_modal == :delete_project} id="delete-project-confirmation">
              <div class="max-h-[calc(100dvh-12rem)] space-y-4 overflow-y-auto p-4 sm:p-6">
                <p class="text-sm leading-6 text-stone-600 dark:text-stone-300">
                  This will move
                  <span class="font-semibold text-stone-950 dark:text-stone-50">
                    {@deleting_project.title}
                  </span>
                  to Recently deleted. You can restore it for 5 days before it is permanently removed.
                </p>
              </div>
              <div class="flex flex-col-reverse gap-2 border-t border-stone-100 bg-stone-50/60 px-4 py-4 sm:flex-row sm:items-center sm:justify-end sm:px-6 dark:border-stone-800 dark:bg-stone-950/40">
                <button
                  type="button"
                  class="w-full rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 sm:w-auto dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                >
                  Cancel
                </button>
                <button
                  id="confirm-delete-project-button"
                  type="button"
                  class="w-full rounded-lg bg-rose-700 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-rose-900/20 transition hover:-translate-y-0.5 hover:bg-rose-800 focus:outline-none focus:ring-2 focus:ring-rose-300 sm:w-auto"
                  phx-click="delete_project"
                  phx-value-id={@deleting_project.id}
                >
                  Delete project
                </button>
              </div>
            </div>

            <div :if={@active_modal == :restore_deleted} id="restore-deleted-modal">
              <div class="max-h-[calc(100dvh-12rem)] space-y-5 overflow-y-auto p-4 sm:p-6">
                <div
                  :if={recovery_empty?(@recently_deleted)}
                  id="recently-deleted-empty"
                  class="rounded-xl border border-dashed border-stone-300 bg-stone-50/80 p-8 text-center dark:border-stone-700 dark:bg-stone-950/60"
                >
                  <p class="font-medium text-stone-950 dark:text-stone-50">
                    No recently deleted items
                  </p>
                  <p class="mt-1 text-sm text-stone-500 dark:text-stone-400">
                    Deleted projects and cards will appear here for 5 days.
                  </p>
                </div>

                <section :if={@recently_deleted.projects != []} id="deleted-projects">
                  <h3 class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                    Projects
                  </h3>
                  <div class="mt-3 space-y-2">
                    <div
                      :for={project <- @recently_deleted.projects}
                      id={"deleted-project-#{project.id}"}
                      class="flex flex-col gap-3 rounded-xl border border-stone-200 bg-white p-3 shadow-sm sm:flex-row sm:items-center sm:justify-between dark:border-stone-700 dark:bg-stone-950"
                    >
                      <div class="min-w-0">
                        <p class="break-words text-sm font-semibold text-stone-950 dark:text-stone-50">
                          {project.title}
                        </p>
                        <p class="mt-1 text-xs text-stone-500 dark:text-stone-400">
                          Project · expires {expires_on(project)}
                        </p>
                      </div>
                      <button
                        id={"restore-deleted-project-#{project.id}"}
                        type="button"
                        class="inline-flex items-center justify-center gap-2 rounded-lg bg-emerald-700 px-3 py-2 text-sm font-semibold text-white shadow-sm shadow-emerald-900/20 transition hover:-translate-y-0.5 hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-300"
                        phx-click="restore_deleted_project"
                        phx-value-id={project.id}
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
                      </button>
                    </div>
                  </div>
                </section>

                <section :if={@recently_deleted.tasks != []} id="deleted-tasks">
                  <h3 class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                    Cards
                  </h3>
                  <div class="mt-3 space-y-2">
                    <div
                      :for={task <- @recently_deleted.tasks}
                      id={"deleted-task-#{task.id}"}
                      class="flex flex-col gap-3 rounded-xl border border-stone-200 bg-white p-3 shadow-sm sm:flex-row sm:items-center sm:justify-between dark:border-stone-700 dark:bg-stone-950"
                    >
                      <div class="min-w-0">
                        <p class="break-words text-sm font-semibold text-stone-950 dark:text-stone-50">
                          {task.title}
                        </p>
                        <p class="mt-1 text-xs text-stone-500 dark:text-stone-400">
                          Card · {task.project.title} · {task.column.name} · expires {expires_on(task)}
                        </p>
                      </div>
                      <button
                        id={"restore-deleted-task-#{task.id}"}
                        type="button"
                        class="inline-flex items-center justify-center gap-2 rounded-lg bg-emerald-700 px-3 py-2 text-sm font-semibold text-white shadow-sm shadow-emerald-900/20 transition hover:-translate-y-0.5 hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-300"
                        phx-click="restore_deleted_task"
                        phx-value-id={task.id}
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
                      </button>
                    </div>
                  </div>
                </section>
              </div>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
