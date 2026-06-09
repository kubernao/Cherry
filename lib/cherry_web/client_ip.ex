defmodule CherryWeb.ClientIP do
  @moduledoc false

  import Plug.Conn

  def get(%Plug.Conn{} = conn) do
    conn
    |> forwarded_for()
    |> first_ip()
    |> case do
      nil -> conn.remote_ip |> :inet.ntoa() |> to_string()
      ip -> ip
    end
  end

  defp forwarded_for(conn) do
    get_req_header(conn, "fly-client-ip") ++ get_req_header(conn, "x-forwarded-for")
  end

  defp first_ip(headers) do
    headers
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
  end
end
