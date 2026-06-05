defmodule Svc.Repo.Migrations.CreateCaptureEvents do
  use Ecto.Migration

  def change do
    create table(:capture_events) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :platform, :string
      add :severity, :string, null: false, default: "info"
      add :detail, :map, null: false, default: %{}
      add :client_session_id, :string
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:capture_events, [:org_id, :occurred_at])
    create index(:capture_events, [:meeting_id])
  end
end
