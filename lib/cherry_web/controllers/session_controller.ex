defmodule CherryWeb.SessionController do
  use CherryWeb, :controller

  alias Cherry.Accounts
  alias Cherry.RateLimit
  alias CherryWeb.ClientIP
  alias CherryWeb.UserAuth

  @login_limit 10
  @login_window_ms :timer.minutes(10)

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in", form: Phoenix.Component.to_form(%{}, as: :user))
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    key = {:login, ClientIP.get(conn), String.downcase(email || "")}

    if RateLimit.allow?(key, @login_limit, @login_window_ms) do
      case Accounts.authenticate_user(email, password) do
        {:ok, user} ->
          RateLimit.reset(key)

          conn
          |> UserAuth.log_in_user(user)
          |> redirect(to: ~p"/")

        :error ->
          conn
          |> put_flash(:error, "Invalid email or password.")
          |> render(:new, page_title: "Sign in", form: Phoenix.Component.to_form(%{}, as: :user))
      end
    else
      conn
      |> put_status(:too_many_requests)
      |> put_flash(:error, "Too many sign-in attempts. Try again later.")
      |> render(:new, page_title: "Sign in", form: Phoenix.Component.to_form(%{}, as: :user))
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/login")
  end
end
