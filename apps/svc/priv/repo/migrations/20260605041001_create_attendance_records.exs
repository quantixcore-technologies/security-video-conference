defmodule Svc.Repo.Migrations.CreateAttendanceRecords do
  use Ecto.Migration

  def change do
    create table(:attendance_records) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :status, :string, null: false
      add :joined_at, :utc_datetime_usec
      add :left_at, :utc_datetime_usec
      add :total_seconds, :integer, null: false, default: 0
      add :source, :string, null: false, default: "livekit_webhook"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:attendance_records, [:meeting_id, :user_id])
    create index(:attendance_records, [:org_id, :user_id])
    create index(:attendance_records, [:meeting_id, :status])
  end
end
