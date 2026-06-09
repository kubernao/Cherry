defmodule Cherry.CLITest do
  use ExUnit.Case

  setup do
    path = Path.join(System.tmp_dir!(), "cherry-cli-#{System.unique_integer([:positive])}.json")
    System.put_env("CHERRY_CONFIG_PATH", path)

    on_exit(fn ->
      System.delete_env("CHERRY_CONFIG_PATH")
      File.rm(path)
    end)

    %{path: path}
  end

  test "stores url and token for agent use", %{path: path} do
    assert {:ok, message} =
             Cherry.CLI.run([
               "auth",
               "login",
               "--url",
               "http://localhost:4000/",
               "--token",
               "cherry_test"
             ])

    assert message =~ path

    assert %{"url" => "http://localhost:4000", "token" => "cherry_test"} =
             path |> File.read!() |> Jason.decode!()

    assert {:ok, %{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "prints succinct agent help without requiring config" do
    for args <- [[], ["--help"], ["-h"], ["help"]] do
      assert {:ok, help} = Cherry.CLI.run(args)
      assert help =~ "Cherry CLI - authenticated access"
      assert help =~ "cherry auth login --url URL --token TOKEN"
      assert help =~ "CHERRY_CONFIG_PATH"
      assert help =~ "Add --json"
      assert help =~ "cherry projects list"
      assert help =~ "cherry projects edit"
      assert help =~ "cherry columns create"
      assert help =~ "cherry tasks create"
      assert help =~ "--tags-json"
      assert help =~ "cherry search QUERY"
      assert help =~ "URL/api/v1"
    end
  end

  test "rejects malformed tag json without requiring config" do
    assert {:error, message} =
             Cherry.CLI.run([
               "tasks",
               "create",
               "--project",
               "1",
               "--title",
               "Tagged",
               "--tags-json",
               "not-json"
             ])

    assert message =~ "invalid --tags-json"
  end

  test "reports missing config before API commands" do
    assert {:error, message} = Cherry.CLI.run(["projects", "list"])
    assert message =~ "not logged in"
  end
end
