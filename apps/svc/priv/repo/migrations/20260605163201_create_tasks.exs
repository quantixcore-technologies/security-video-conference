defmodule Svc.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all)
      add :assignee_id, references(:users, on_delete: :nilify_all)
      add :meeting_id, references(:meetings, on_delete: :nilify_all)

      add :title, :string, null: false
      add :description, :text
      add :priority, :string, null: false, default: "normal"
      add :status, :string, null: false, default: "todo"
      add :due_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:org_id, :status])
    create index(:tasks, [:assignee_id])
    create index(:tasks, [:meeting_id])
  end
end
