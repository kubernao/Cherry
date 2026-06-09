defmodule Cherry.Workspace.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Workspace.Task

  schema "tags" do
    field :name, :string
    field :color, :string, default: "neutral"

    many_to_many :tasks, Task, join_through: "task_tags"

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name, :color])
    |> update_change(:name, &String.downcase/1)
    |> unique_constraint(:name)
  end
end
