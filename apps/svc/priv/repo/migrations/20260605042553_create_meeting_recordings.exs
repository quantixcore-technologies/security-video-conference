defmodule Svc.Repo.Migrations.CreateMeetingRecordings do
  use Ecto.Migration

  def change do
    create table(:meeting_recordings) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :requested_by, references(:users, on_delete: :nilify_all)

      add :egress_id, :string
      add :storage_path, :string
      add :encrypted, :boolean, null: false, default: true
      add :status, :string, null: false, default: "starting"
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:meeting_recordings, [:org_id])
    create index(:meeting_recordings, [:meeting_id])
    create unique_index(:meeting_recordings, [:egress_id])
  end
end
