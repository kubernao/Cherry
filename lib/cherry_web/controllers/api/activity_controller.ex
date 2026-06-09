defmodule CherryWeb.Api.ActivityController do
  use CherryWeb, :controller

  alias Cherry.Workspace

  def index(conn, _params) do
    events =
      Workspace.list_activity()
      |> Enum.map(fn event ->
        %{
          id: event.id,
          actor: event.actor,
          action: event.action,
          entity_type: event.entity_type,
          entity_id: event.entity_id,
          metadata: event.metadata,
          inserted_at: event.inserted_at
        }
      end)

    json(conn, %{activity: events})
  end
end
