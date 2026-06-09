defmodule CherryWeb.SessionController do
  use CherryWeb, :controller

  alias Cherry.Accounts
  alias CherryWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in", form: Phoenix.Component.to_form(%{}, as: :user))
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> render(:new, page_title: "Sign in", form: Phoenix.Component.to_form(%{}, as: :user))
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/login")
  end
end
