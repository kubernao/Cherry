defmodule Cherry.AccountsTest do
  use Cherry.DataCase

  alias Cherry.Accounts

  test "authenticates owner and api token scopes" do
    user =
      Accounts.ensure_owner!(%{email: "owner@example.com", password: "super-secret-password"})

    assert {:ok, authed_user} =
             Accounts.authenticate_user("owner@example.com", "super-secret-password")

    assert authed_user.id == user.id
    assert :error = Accounts.authenticate_user("owner@example.com", "wrong-password")

    assert {:ok, raw, token} =
             Accounts.create_api_token(user, %{name: "agent", scopes: "read,write"})

    assert {:ok, authed} = Accounts.authenticate_api_token(raw)
    assert authed.id == token.id
    assert Accounts.token_has_scope?(authed, :read)
    assert Accounts.token_has_scope?(authed, :write)
    refute Accounts.token_has_scope?(authed, :admin)
  end
end
