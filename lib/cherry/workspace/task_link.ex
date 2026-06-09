defmodule Cherry.Workspace.TaskLink do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Workspace.Task

  schema "task_links" do
    field :kind, :string, default: "blocks"

    belongs_to :source_task, Task
    belongs_to :target_task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:source_task_id, :target_task_id, :kind])
    |> validate_required([:source_task_id, :target_task_id, :kind])
    |> validate_inclusion(:kind, ["blocks", "relates"])
    |> validate_not_self_link()
    |> unique_constraint([:source_task_id, :target_task_id, :kind])
  end

  defp validate_not_self_link(changeset) do
    source = get_field(changeset, :source_task_id)
    target = get_field(changeset, :target_task_id)

    if source && target && source == target do
      add_error(changeset, :source_task_id, "cannot link a task to itself")
    else
      changeset
    end
  end
end
