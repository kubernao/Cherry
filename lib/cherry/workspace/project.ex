defmodule Cherry.Workspace.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cherry.Workspace.{Column, Task}

  @statuses ~w(active paused done)
  @priorities ~w(low normal high urgent)

  schema "projects" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "active"
    field :priority, :string, default: "normal"
    field :archived, :boolean, default: false
    field :deleted_at, :utc_datetime

    has_many :columns, Column
    has_many :tasks, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :slug, :description, :status, :priority, :archived])
    |> validate_required([:title, :status, :priority])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> put_slug()
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      value when is_binary(value) and value != "" -> update_change(changeset, :slug, &slugify/1)
      _ -> put_change(changeset, :slug, slugify(get_field(changeset, :title) || "project"))
    end
  end

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "project"
      slug -> slug
    end
  end
end
