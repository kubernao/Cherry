defmodule CherryWeb.HealthController do
  use CherryWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
