defmodule Cherry.Workspace.ActivityEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Accounts.User

  schema "activity_events" do
    field :actor, :string, default: "system"
    field :action, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:user_id, :actor, :action, :entity_type, :entity_id, :metadata])
    |> validate_required([:actor, :action, :entity_type, :entity_id])
  end
end
