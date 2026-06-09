defmodule CherryWeb.PageController do
  use CherryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
