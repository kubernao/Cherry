defmodule Cherry.Workspace.Column do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Workspace.{Project, Task}

  schema "columns" do
    field :name, :string
    field :position, :integer

    belongs_to :project, Project
    has_many :tasks, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :position, :project_id])
    |> validate_required([:name, :position, :project_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
