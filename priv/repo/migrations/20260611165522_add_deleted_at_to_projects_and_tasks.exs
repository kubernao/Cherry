defmodule Cherry.Repo.Migrations.AddDeletedAtToProjectsAndTasks do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :deleted_at, :utc_datetime
    end

    alter table(:tasks) do
      add :deleted_at, :utc_datetime
    end

    create index(:projects, [:deleted_at])
    create index(:tasks, [:deleted_at])
  end
end
