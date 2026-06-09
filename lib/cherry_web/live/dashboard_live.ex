defmodule CherryWeb.DashboardLive do
  use CherryWeb, :live_view

  alias Cherry.Workspace

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:query, "")
     |> assign(:active_modal, nil)
     |> assign(:project_form, to_form(%{"title" => "", "description" => ""}, as: :project))
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

  def handle_event("open_modal", %{"modal" => "new_project"}, socket) do
    {:noreply, assign(socket, :active_modal, :new_project)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :active_modal, nil)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    results = if String.trim(query) == "", do: nil, else: Workspace.search(query)
    {:noreply, assign(socket, query: query, search_results: results)}
  end

  defp load_projects(socket) do
    socket
    |> assign(:projects, Workspace.list_projects())
    |> assign(:archived_projects, Workspace.list_projects(archived: true))
    |> assign(:search_results, nil)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="space-y-6" phx-window-keydown="close_modal" phx-key="escape">
        <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-sm font-semibold text-rose-700 dark:text-rose-300">Workspace</p>
            <h1 class="mt-1 text-3xl font-semibold tracking-normal text-stone-950 dark:text-stone-50">
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
              class="inline-flex items-center justify-center gap-2 rounded-xl bg-stone-950 px-4 py-2.5 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
              phx-click="open_modal"
              phx-value-modal="new_project"
            >
              <.icon name="hero-plus" class="size-4" />
              <span class="hidden sm:inline">New project</span>
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
              <.link
                :for={project <- @projects}
                navigate={~p"/projects/#{project.id}"}
                id={"project-card-#{project.id}"}
                class="group block rounded-xl border border-stone-200 bg-white/85 p-4 shadow-sm transition hover:-translate-y-1 hover:border-stone-300 hover:bg-white hover:shadow-md dark:border-stone-700 dark:bg-stone-900/85 dark:hover:border-stone-600 dark:hover:bg-stone-900"
              >
                <div class="flex items-start justify-between gap-3">
                  <h2 class="font-semibold text-stone-950 dark:text-stone-50">{project.title}</h2>
                  <span class="rounded-md bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700 dark:bg-rose-950/50 dark:text-rose-300">
                    {project.priority}
                  </span>
                </div>
                <p class="mt-3 line-clamp-3 min-h-12 text-sm leading-6 text-stone-600 dark:text-stone-300">
                  {project.description}
                </p>
                <div class="mt-4 flex items-center justify-between">
                  <p class="text-xs font-semibold uppercase text-stone-500 dark:text-stone-400">
                    {project.status}
                  </p>
                  <span class="rounded-md p-1 text-stone-300 transition group-hover:bg-stone-100 group-hover:text-stone-700 dark:text-stone-500 dark:group-hover:bg-stone-800 dark:group-hover:text-stone-100">
                    <.icon name="hero-arrow-right" class="size-4" />
                  </span>
                </div>
              </.link>
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
            <.link
              :for={project <- @archived_projects}
              navigate={~p"/projects/#{project.id}"}
              class="rounded-lg border border-stone-200 bg-white px-3 py-2 text-sm text-stone-600 transition hover:-translate-y-0.5 hover:border-stone-300 hover:text-stone-950 dark:border-stone-700 dark:bg-stone-950 dark:text-stone-300 dark:hover:border-stone-600 dark:hover:text-stone-50"
            >
              {project.title}
            </.link>
          </div>
        </section>

        <div
          :if={@active_modal == :new_project}
          id="dashboard-modal-backdrop"
          class="fixed inset-0 z-50 grid place-items-center overflow-y-auto px-4 py-8"
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
            class="relative w-full max-w-2xl overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-2xl shadow-stone-950/20 dark:border-stone-700 dark:bg-stone-900 dark:shadow-black/50"
          >
            <div class="border-b border-stone-100 bg-stone-50/80 px-6 py-5 dark:border-stone-800 dark:bg-stone-950/70">
              <div class="flex items-start justify-between gap-4">
                <div class="flex min-w-0 gap-4">
                  <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-rose-50 text-rose-700 ring-1 ring-rose-100 dark:bg-rose-950/40 dark:text-rose-300 dark:ring-rose-900/60">
                    <.icon name="hero-folder-plus" class="size-5" />
                  </span>
                  <div>
                    <p class="text-xs font-semibold uppercase text-rose-700 dark:text-rose-300">
                      Project
                    </p>
                    <h2 class="mt-1 text-xl font-semibold text-stone-950 dark:text-stone-50">
                      Create a new project
                    </h2>
                    <p class="mt-1 max-w-lg text-sm leading-6 text-stone-500 dark:text-stone-400">
                      Give it a clear name and a short note so the board opens with useful context.
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
              id="project-form"
              for={@project_form}
              phx-submit="create_project"
              class="cherry-form"
            >
              <div class="space-y-5 p-6">
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
              </div>
              <div class="flex items-center justify-end gap-2 border-t border-stone-100 bg-stone-50/60 px-6 py-4 dark:border-stone-800 dark:bg-stone-950/40">
                <button
                  type="button"
                  class="rounded-lg px-4 py-2 text-sm font-semibold text-stone-500 transition hover:bg-stone-100 hover:text-stone-900 dark:text-stone-400 dark:hover:bg-stone-800 dark:hover:text-stone-100"
                  phx-click="close_modal"
                >
                  Cancel
                </button>
                <button
                  id="create-project-button"
                  class="rounded-lg bg-stone-950 px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-stone-900/20 transition hover:-translate-y-0.5 hover:bg-stone-800 focus:outline-none focus:ring-2 focus:ring-rose-300 dark:bg-stone-50 dark:text-stone-950 dark:hover:bg-white"
                  type="submit"
                >
                  Create project
                </button>
              </div>
            </.form>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
