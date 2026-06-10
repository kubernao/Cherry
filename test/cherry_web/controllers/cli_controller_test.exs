defmodule CherryWeb.CliControllerTest do
  use CherryWeb.ConnCase

  alias Cherry.Accounts

  defp log_in(conn) do
    user =
      Accounts.ensure_owner!(%{email: "owner@example.com", password: "super-secret-password"})

    {Plug.Test.init_test_session(conn, user_id: user.id), user}
  end

  test "requires sign in to create a command-line link", %{conn: conn} do
    conn = post(conn, ~p"/cli/link")

    assert redirected_to(conn) == ~p"/login"
  end

  test "creates a setup page with bash and powershell install commands", %{conn: conn} do
    {conn, _user} = log_in(conn)

    conn = post(conn, ~p"/cli/link")
    html = html_response(conn, 200)

    assert html =~ "Link to AI in command line"
    assert html =~ "curl -fsSL http://www.example.com/cli/install/sh/cherry_"
    assert html =~ "irm http://www.example.com/cli/install/ps1/cherry_"
    assert html =~ "copy-cli-link-bash"
    assert html =~ "copy-cli-link-powershell"
  end

  test "serves bash installer for a valid generated token", %{conn: conn} do
    {_conn, user} = log_in(conn)

    {:ok, raw, _token} =
      Accounts.create_api_token(user, %{name: "test cli", scopes: "read,write"})

    conn = get(conn, ~p"/cli/install/sh/#{raw}")

    assert response(conn, 200) =~ "Cherry CLI installed"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "rejects invalid installer tokens", %{conn: conn} do
    conn = get(conn, ~p"/cli/install/sh/cherry_invalid")

    assert response(conn, 404) == "not found"
  end
end
