defmodule Cherry.AccountsTest do
  use Cherry.DataCase

  import ExUnit.CaptureIO

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

  test "bootstraps first owner from environment and refuses a second owner" do
    System.put_env("OWNER_EMAIL", "secure-owner@example.com")
    System.put_env("OWNER_PASSWORD", "super-secret-password")

    on_exit(fn ->
      System.delete_env("OWNER_EMAIL")
      System.delete_env("OWNER_PASSWORD")
    end)

    output = capture_io(fn -> Cherry.Release.bootstrap_owner() end)

    assert output =~ "Owner created"
    assert output =~ "secure-owner@example.com"
    assert output =~ "Initial API token"

    output = capture_io(fn -> Cherry.Release.bootstrap_owner() end)
    assert output =~ "Owner already exists"
  end

  test "owner bootstrap refuses unsafe default credentials" do
    System.put_env("OWNER_EMAIL", "owner@example.com")
    System.put_env("OWNER_PASSWORD", "change-me-now!")

    on_exit(fn ->
      System.delete_env("OWNER_EMAIL")
      System.delete_env("OWNER_PASSWORD")
    end)

    assert_raise RuntimeError, ~r/OWNER_EMAIL/, fn ->
      Cherry.Release.bootstrap_owner()
    end
  end
end
