defmodule Svc.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      # org переживает (nilify), лог не каскадит
      add :org_id, references(:organizations, on_delete: :nilify_all)

      # НЕ FK: лог переживает удаление актора (D-014, append-only аудит)
      add :actor_user_id, :bigint
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :metadata, :map, null: false, default: %{}
      add :ip, :string
      add :user_agent, :string

      # append-only: только inserted_at
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_logs, [:org_id, :inserted_at])
    create index(:audit_logs, [:actor_user_id])
    create index(:audit_logs, [:resource_type, :resource_id])
  end
end
