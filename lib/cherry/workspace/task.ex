defmodule Cherry.Workspace.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Workspace.{Column, Project, Tag, TaskLink}

  @statuses ~w(open in_progress done)
  @priorities ~w(low normal high urgent)

  schema "tasks" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "open"
    field :priority, :string, default: "normal"
    field :due_date, :date
    field :archived, :boolean, default: false
    field :deleted_at, :utc_datetime
    field :position, :integer

    belongs_to :project, Project
    belongs_to :column, Column
    many_to_many :tags, Tag, join_through: "task_tags", on_replace: :delete
    has_many :blocking_links, TaskLink, foreign_key: :source_task_id
    has_many :blocked_by_links, TaskLink, foreign_key: :target_task_id

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :body,
      :status,
      :priority,
      :due_date,
      :archived,
      :position,
      :project_id,
      :column_id
    ])
    |> validate_required([:title, :status, :priority, :position, :project_id, :column_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
