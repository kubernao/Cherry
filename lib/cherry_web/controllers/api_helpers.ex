defmodule CherryWeb.ApiHelpers do
  import Phoenix.Controller
  import Plug.Conn

  def render_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_failed", fields: errors_on(changeset)}})
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def render_operation_error(conn, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "operation_failed", reason: to_string(reason)}})
  end
end
