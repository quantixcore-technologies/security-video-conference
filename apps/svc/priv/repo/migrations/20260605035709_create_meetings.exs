defmodule Svc.Repo.Migrations.CreateMeetings do
  use Ecto.Migration

  def change do
    create table(:meetings) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      # nullable: встреча-история переживает удаление организатора (nilify)
      add :organizer_id, references(:users, on_delete: :nilify_all)

      add :title, :string, null: false
      add :type, :string, null: false, default: "scheduled"
      add :status, :string, null: false, default: "planned"
      add :scheduled_start, :utc_datetime_usec
      add :scheduled_end, :utc_datetime_usec
      add :livekit_room_name, :string, null: false
      add :recording_policy, :string, null: false, default: "off"
      add :late_threshold_seconds, :integer, null: false, default: 300

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:meetings, [:livekit_room_name])
    create index(:meetings, [:org_id, :status])
    create index(:meetings, [:organizer_id])
  end
end
