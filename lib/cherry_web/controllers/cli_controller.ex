defmodule CherryWeb.CliController do
  use CherryWeb, :controller

  alias Cherry.Accounts

  def create(conn, _params) do
    user = conn.assigns.current_user

    with {:ok, raw, _token} <-
           Accounts.create_api_token(user, %{
             name: "Command line AI link",
             scopes: "read,write"
           }) do
      render(conn, :setup,
        page_title: "Link to AI in command line",
        current_user: user,
        bash_command: install_command(conn, "sh", raw),
        powershell_command: install_command(conn, "ps1", raw)
      )
    end
  end

  def install(conn, %{"platform" => "sh", "token" => token}) do
    serve_installer(conn, token, &bash_installer/2, "text/x-shellscript")
  end

  def install(conn, %{"platform" => "ps1", "token" => token}) do
    serve_installer(conn, token, &powershell_installer/2, "text/plain")
  end

  def install(conn, _params), do: send_resp(conn, :not_found, "not found")

  defp serve_installer(conn, token, builder, content_type) do
    case Accounts.authenticate_api_token(token) do
      {:ok, _api_token} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(:ok, builder.(base_url(conn), token))

      :error ->
        send_resp(conn, :not_found, "not found")
    end
  end

  defp install_command(conn, platform, token) do
    url = "#{base_url(conn)}/cli/install/#{platform}/#{token}"

    case platform do
      "sh" -> "curl -fsSL #{url} | bash"
      "ps1" -> "irm #{url} | iex"
    end
  end

  defp base_url(conn) do
    scheme = Atom.to_string(conn.scheme)

    default_port? =
      (conn.scheme == :http and conn.port == 80) or (conn.scheme == :https and conn.port == 443)

    port = if default_port?, do: "", else: ":#{conn.port}"

    "#{scheme}://#{conn.host}#{port}"
  end

  defp bash_installer(url, token) do
    config = Jason.encode!(%{url: url, token: token}, pretty: true)
    config64 = Base.encode64(config)
    launcher64 = Base.encode64(bash_launcher())

    """
    #!/usr/bin/env bash
    set -euo pipefail

    install_dir="${CHERRY_BIN_DIR:-$HOME/.local/bin}"
    config_dir="${CHERRY_CONFIG_DIR:-$HOME/.config/cherry}"
    config_path="${CHERRY_CONFIG_PATH:-$config_dir/config.json}"

    mkdir -p "$install_dir" "$config_dir"
    chmod 700 "$config_dir"

    decode64() {
      if base64 --help 2>&1 | grep -q -- "-d"; then
        base64 -d
      else
        base64 -D
      fi
    }

    printf '%s' '#{config64}' | decode64 > "$config_path"
    chmod 600 "$config_path"
    printf '%s' '#{launcher64}' | decode64 > "$install_dir/cherry"
    chmod 755 "$install_dir/cherry"

    echo "Cherry CLI installed at $install_dir/cherry"
    echo "Credentials saved to $config_path"
    case ":$PATH:" in
      *":$install_dir:"*) ;;
      *) echo "Add $install_dir to PATH if 'cherry' is not found." ;;
    esac
    """
  end

  defp powershell_installer(url, token) do
    config = Jason.encode!(%{url: url, token: token}, pretty: true)
    config64 = Base.encode64(config)
    launcher64 = Base.encode64(powershell_launcher())

    """
    $ErrorActionPreference = "Stop"

    $installDir = if ($env:CHERRY_BIN_DIR) { $env:CHERRY_BIN_DIR } else { Join-Path $HOME ".local\\bin" }
    $configDir = if ($env:CHERRY_CONFIG_DIR) { $env:CHERRY_CONFIG_DIR } else { Join-Path $HOME ".config\\cherry" }
    $configPath = if ($env:CHERRY_CONFIG_PATH) { $env:CHERRY_CONFIG_PATH } else { Join-Path $configDir "config.json" }

    New-Item -ItemType Directory -Force -Path $installDir, $configDir | Out-Null
    [IO.File]::WriteAllText($configPath, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("#{config64}")))
    [IO.File]::WriteAllText((Join-Path $installDir "cherry.ps1"), [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("#{launcher64}")))

    Write-Host "Cherry CLI installed at $(Join-Path $installDir 'cherry.ps1')"
    Write-Host "Credentials saved to $configPath"
    Write-Host "Add $installDir to PATH if 'cherry.ps1' is not found."
    """
  end

  defp bash_launcher do
    """
    #!/usr/bin/env bash
    set -euo pipefail

    config_path="${CHERRY_CONFIG_PATH:-$HOME/.config/cherry/config.json}"

    if [ ! -f "$config_path" ]; then
      echo "not logged in; run the Cherry command-line link from the web app again" >&2
      exit 1
    fi

    read_config() {
      python3 - "$config_path" <<'PY'
    import json, sys
    with open(sys.argv[1], encoding="utf-8") as f:
      data = json.load(f)
    print(data["url"].rstrip("/") + "\\t" + data["token"])
    PY
    }

    IFS=$'\\t' read -r cherry_url cherry_token < <(read_config)

    api() {
      local method="$1"
      local path="$2"
      local body="${3:-}"
      if [ -n "$body" ]; then
        curl -fsS -X "$method" "$cherry_url/api/v1$path" \\
          -H "authorization: Bearer $cherry_token" \\
          -H "accept: application/json" \\
          -H "content-type: application/json" \\
          --data "$body"
      else
        curl -fsS -X "$method" "$cherry_url/api/v1$path" \\
          -H "authorization: Bearer $cherry_token" \\
          -H "accept: application/json"
      fi
      printf '\\n'
    }

    case "${1:-}" in
      api)
        shift
        api "${1:-GET}" "${2:-/projects}" "${3:-}"
        ;;
      projects)
        case "${2:-list}" in
          list) api GET "/projects" ;;
          show) api GET "/projects/${3:?project id required}" ;;
          *) echo "usage: cherry projects list|show PROJECT_ID" >&2; exit 1 ;;
        esac
        ;;
      tasks)
        case "${2:-list}" in
          list) api GET "/tasks" ;;
          show) api GET "/tasks/${3:?task id required}" ;;
          *) echo "usage: cherry tasks list|show TASK_ID" >&2; exit 1 ;;
        esac
        ;;
      search)
        query="${2:?search query required}"
        api GET "/search?q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$query")"
        ;;
      activity)
        api GET "/activity"
        ;;
      *)
        cat <<'HELP'
    Cherry CLI

    Commands:
      cherry projects list
      cherry projects show PROJECT_ID
      cherry tasks list
      cherry tasks show TASK_ID
      cherry search QUERY
      cherry activity
      cherry api METHOD /path [json]
    HELP
        ;;
    esac
    """
  end

  defp powershell_launcher do
    """
    $ErrorActionPreference = "Stop"

    $configPath = if ($env:CHERRY_CONFIG_PATH) { $env:CHERRY_CONFIG_PATH } else { Join-Path $HOME ".config\\cherry\\config.json" }
    if (!(Test-Path $configPath)) {
      Write-Error "not logged in; run the Cherry command-line link from the web app again"
      exit 1
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $baseUrl = $config.url.TrimEnd("/")
    $headers = @{
      authorization = "Bearer $($config.token)"
      accept = "application/json"
    }

    function Invoke-CherryApi($method, $path, $body = $null) {
      $params = @{
        Method = $method
        Uri = "$baseUrl/api/v1$path"
        Headers = $headers
      }
      if ($body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = $body
      }
      Invoke-RestMethod @params | ConvertTo-Json -Depth 20
    }

    if ($args.Count -eq 0) {
      Write-Host "Cherry CLI"
      Write-Host "Commands: projects list, projects show PROJECT_ID, tasks list, tasks show TASK_ID, search QUERY, activity, api METHOD /path [json]"
      exit 0
    }

    switch ($args[0]) {
      "api" {
        $method = if ($args.Count -gt 1) { $args[1] } else { "GET" }
        $path = if ($args.Count -gt 2) { $args[2] } else { "/projects" }
        $body = if ($args.Count -gt 3) { $args[3] } else { $null }
        Invoke-CherryApi $method $path $body
      }
      "projects" {
        switch ($args[1]) {
          "show" { Invoke-CherryApi "GET" "/projects/$($args[2])" }
          default { Invoke-CherryApi "GET" "/projects" }
        }
      }
      "tasks" {
        switch ($args[1]) {
          "show" { Invoke-CherryApi "GET" "/tasks/$($args[2])" }
          default { Invoke-CherryApi "GET" "/tasks" }
        }
      }
      "search" { Invoke-CherryApi "GET" "/search?q=$([uri]::EscapeDataString($args[1]))" }
      "activity" { Invoke-CherryApi "GET" "/activity" }
      default { Write-Error "unknown command" }
    }
    """
  end
end
