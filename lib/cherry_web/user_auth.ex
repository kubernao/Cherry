defmodule CherryWeb.UserAuth do
  import Phoenix.Controller
  import Plug.Conn

  alias Cherry.Accounts

  def init(action), do: action
  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])
  def call(conn, :require_authenticated_user), do: require_authenticated_user(conn, [])

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = if user_id, do: Accounts.get_user!(user_id), else: nil
    assign(conn, :current_user, user)
  rescue
    Ecto.NoResultsError ->
      conn
      |> configure_session(drop: true)
      |> assign(:current_user, nil)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Sign in to continue.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> delete_resp_cookie("_cherry_key")
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> Accounts.get_user!(id)
      end

    {:cont, Phoenix.Component.assign(socket, :current_user, user)}
  rescue
    Ecto.NoResultsError -> {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}

      id ->
        {:cont, Phoenix.Component.assign(socket, :current_user, Accounts.get_user!(id))}
    end
  rescue
    Ecto.NoResultsError -> {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
