defmodule Cherry.Repo.Migrations.CreateWorkspace do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:api_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :scopes, :string, null: false, default: "read"
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:user_id])

    create table(:projects) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :priority, :string, null: false, default: "normal"
      add :archived, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:slug])
    create index(:projects, [:archived])

    create table(:columns) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:columns, [:project_id])
    create unique_index(:columns, [:project_id, :position])

    create table(:tasks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :column_id, references(:columns, on_delete: :nilify_all), null: false
      add :title, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "open"
      add :priority, :string, null: false, default: "normal"
      add :due_date, :date
      add :archived, :boolean, null: false, default: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:column_id])
    create index(:tasks, [:archived])
    create index(:tasks, [:due_date])

    create table(:task_links) do
      add :source_task_id, references(:tasks, on_delete: :delete_all), null: false
      add :target_task_id, references(:tasks, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "blocks"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:task_links, [:source_task_id, :target_task_id, :kind])

    create table(:tags) do
      add :name, :string, null: false
      add :color, :string, null: false, default: "neutral"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:name])

    create table(:task_tags) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:task_tags, [:task_id, :tag_id])

    create table(:activity_events) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :actor, :string, null: false, default: "system"
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :integer, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:activity_events, [:entity_type, :entity_id])
    create index(:activity_events, [:inserted_at])
  end
end
