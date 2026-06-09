defmodule Cherry.CLI do
  @moduledoc false

  def main(args) do
    case run(args) do
      {:ok, output} when is_binary(output) ->
        IO.puts(output)

      {:ok, _} ->
        :ok

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  def run(["auth", "login" | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [url: :string, token: :string])

    with url when is_binary(url) <- opts[:url] || {:error, "missing --url"},
         token when is_binary(token) <- opts[:token] || {:error, "missing --token"} do
      File.mkdir_p!(config_dir())

      File.write!(
        config_path(),
        Jason.encode!(%{url: String.trim_trailing(url, "/"), token: token}, pretty: true)
      )

      {:ok, "Saved Cherry CLI credentials to #{config_path()}"}
    else
      {:error, message} -> {:error, message}
    end
  end

  def run(["projects", "list" | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean, archived: :boolean])

    request(:get, "/projects", params: [archived: opts[:archived] || false])
    |> render(opts, fn body -> table(body["projects"], ["id", "title", "status", "priority"]) end)
  end

  def run(["projects", "create" | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [title: :string, description: :string, json: :boolean])

    request(:post, "/projects",
      json: %{project: %{title: opts[:title], description: opts[:description]}}
    )
    |> render(opts, fn body ->
      "Created project #{body["project"]["id"]}: #{body["project"]["title"]}"
    end)
  end

  def run(["projects", "show", id | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:get, "/projects/#{id}")
    |> render(opts, fn body -> Jason.encode!(body["project"], pretty: true) end)
  end

  def run(["projects", "archive", id | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:post, "/projects/#{id}/archive")
    |> render(opts, fn body -> "Archived project #{body["project"]["id"]}" end)
  end

  def run(["tasks", "list" | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [project: :string, archived: :boolean, json: :boolean])

    query =
      Enum.reject([project_id: opts[:project], archived: opts[:archived] || false], fn {_k, v} ->
        is_nil(v)
      end)

    request(:get, "/tasks", params: query)
    |> render(opts, fn body ->
      table(body["tasks"], ["id", "title", "status", "priority", "due_date"])
    end)
  end

  def run(["tasks", "create" | args]) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          project: :string,
          column: :string,
          title: :string,
          body: :string,
          priority: :string,
          due: :string,
          tags: :string,
          json: :boolean
        ]
      )

    task =
      %{
        project_id: opts[:project],
        column_id: opts[:column],
        title: opts[:title],
        body: opts[:body],
        priority: opts[:priority] || "normal",
        due_date: opts[:due],
        tags: opts[:tags]
      }
      |> drop_nil()

    request(:post, "/tasks", json: %{task: task})
    |> render(opts, fn body -> "Created task #{body["task"]["id"]}: #{body["task"]["title"]}" end)
  end

  def run(["tasks", "show", id | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:get, "/tasks/#{id}")
    |> render(opts, fn body -> Jason.encode!(body["task"], pretty: true) end)
  end

  def run(["tasks", "edit", id | args]) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          title: :string,
          body: :string,
          priority: :string,
          status: :string,
          due: :string,
          tags: :string,
          json: :boolean
        ]
      )

    task =
      %{
        title: opts[:title],
        body: opts[:body],
        priority: opts[:priority],
        status: opts[:status],
        due_date: opts[:due],
        tags: opts[:tags]
      }
      |> drop_nil()

    request(:patch, "/tasks/#{id}", json: %{task: task})
    |> render(opts, fn body -> "Updated task #{body["task"]["id"]}: #{body["task"]["title"]}" end)
  end

  def run(["tasks", "move", id | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [column: :string, position: :integer, json: :boolean])

    request(:post, "/tasks/#{id}/move",
      json: %{column_id: opts[:column], position: opts[:position] || 0}
    )
    |> render(opts, fn body -> "Moved task #{body["task"]["id"]}" end)
  end

  def run(["tasks", "done", id | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:post, "/tasks/#{id}/done")
    |> render(opts, fn body -> "Completed task #{body["task"]["id"]}" end)
  end

  def run(["tasks", "archive", id | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:post, "/tasks/#{id}/archive")
    |> render(opts, fn body -> "Archived task #{body["task"]["id"]}" end)
  end

  def run(["search", query | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:get, "/search", params: [q: query])
    |> render(opts, fn body ->
      projects = table(body["projects"], ["id", "title", "status"])
      tasks = table(body["tasks"], ["id", "title", "status", "priority"])
      "Projects\n#{projects}\n\nTasks\n#{tasks}"
    end)
  end

  def run(["activity" | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [json: :boolean])

    request(:get, "/activity")
    |> render(opts, fn body ->
      table(body["activity"], ["id", "actor", "action", "entity_type", "entity_id"])
    end)
  end

  def run(_args), do: {:error, usage()}

  defp request(method, path, opts \\ []) do
    with {:ok, config} <- read_config() do
      {:ok, _} = Application.ensure_all_started(:req)
      url = config.url <> "/api/v1" <> path
      headers = [{"authorization", "Bearer #{config.token}"}, {"accept", "application/json"}]

      case Req.request(Keyword.merge(opts, method: method, url: url, headers: headers)) do
        {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{Jason.encode!(body)}"}
        {:error, error} -> {:error, Exception.message(error)}
      end
    end
  end

  defp read_config do
    case File.read(config_path()) do
      {:ok, body} ->
        {:ok, body |> Jason.decode!() |> then(&%{url: &1["url"], token: &1["token"]})}

      {:error, _} ->
        {:error, "not logged in; run cherry auth login --url URL --token TOKEN"}
    end
  end

  defp config_dir, do: Path.dirname(config_path())

  defp config_path do
    System.get_env("CHERRY_CONFIG_PATH") ||
      Path.join([System.user_home!(), ".config", "cherry", "config.json"])
  end

  defp render({:ok, body}, opts, human_fun) do
    if opts[:json], do: {:ok, Jason.encode!(body, pretty: true)}, else: {:ok, human_fun.(body)}
  end

  defp render({:error, message}, _opts, _human_fun), do: {:error, message}

  defp table(rows, keys) do
    rows = rows || []

    widths =
      Enum.map(keys, fn key ->
        max(String.length(key), rows |> Enum.map(&cell_width(&1[key])) |> Enum.max(fn -> 0 end))
      end)

    header = render_row(keys, widths)
    sep = widths |> Enum.map(&String.duplicate("-", &1)) |> Enum.join("-+-")

    body =
      rows
      |> Enum.map(&render_row(Enum.map(keys, fn key -> &1[key] end), widths))
      |> Enum.join("\n")

    Enum.reject([header, sep, body], &(&1 == "")) |> Enum.join("\n")
  end

  defp render_row(values, widths) do
    values
    |> Enum.zip(widths)
    |> Enum.map(fn {value, width} -> value |> to_string() |> String.pad_trailing(width) end)
    |> Enum.join(" | ")
  end

  defp cell_width(nil), do: 0
  defp cell_width(value), do: value |> to_string() |> String.length()

  defp drop_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) or value == "" end)

  defp usage do
    """
    cherry auth login --url URL --token TOKEN
    cherry projects list|create|show|archive
    cherry tasks list|create|show|edit|move|done|archive
    cherry search QUERY
    cherry activity
    """
  end
end
