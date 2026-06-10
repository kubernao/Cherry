defmodule CherryWeb.Router do
  use CherryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CherryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CherryWeb.UserAuth, :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_read do
    plug CherryWeb.ApiAuth, scope: :read
  end

  pipeline :api_write do
    plug CherryWeb.ApiAuth, scope: :write
  end

  pipeline :require_authenticated_user do
    plug CherryWeb.UserAuth, :require_authenticated_user
  end

  scope "/", CherryWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    get "/health", HealthController, :show
    get "/cli/install/:platform/:token", CliController, :install
  end

  scope "/", CherryWeb do
    pipe_through [:browser, :require_authenticated_user]

    post "/cli/link", CliController, :create

    live_session :authenticated, on_mount: [{CherryWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive, :index
      live "/projects/:id", ProjectLive, :show
    end
  end

  scope "/api/v1", CherryWeb.Api, as: :api do
    pipe_through [:api, :api_read]

    get "/projects", ProjectController, :index
    get "/projects/:id", ProjectController, :show
    get "/columns", ColumnController, :index
    get "/tasks", TaskController, :index
    get "/tasks/:id", TaskController, :show
    get "/search", SearchController, :index
    get "/activity", ActivityController, :index
  end

  scope "/api/v1", CherryWeb.Api, as: :api do
    pipe_through [:api, :api_write]

    post "/projects", ProjectController, :create
    patch "/projects/:id", ProjectController, :update
    post "/projects/:id/archive", ProjectController, :archive
    post "/projects/:id/restore", ProjectController, :restore
    delete "/projects/:id", ProjectController, :delete
    post "/columns", ColumnController, :create
    patch "/columns/:id", ColumnController, :update
    post "/columns/:id/move", ColumnController, :move
    delete "/columns/:id", ColumnController, :delete
    post "/tasks", TaskController, :create
    patch "/tasks/:id", TaskController, :update
    post "/tasks/:id/move", TaskController, :move
    post "/tasks/:id/done", TaskController, :done
    post "/tasks/:id/archive", TaskController, :archive
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cherry, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CherryWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
