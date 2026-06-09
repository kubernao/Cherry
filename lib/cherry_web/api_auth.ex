defmodule CherryWeb.ApiAuth do
  import Plug.Conn

  alias Cherry.Accounts

  def init(opts), do: opts

  def call(conn, opts) do
    required_scope = Keyword.get(opts, :scope, :read)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_token} <- Accounts.authenticate_api_token(token),
         true <- Accounts.token_has_scope?(api_token, required_scope) do
      conn
      |> assign(:api_token, api_token)
      |> assign(:current_user, api_token.user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          :unauthorized,
          Jason.encode!(%{error: %{code: "unauthorized", message: "valid bearer token required"}})
        )
        |> halt()
    end
  end
end
