defmodule Svc.Repo.Migrations.CreateMeetingInvitees do
  use Ecto.Migration

  def change do
    create table(:meeting_invitees) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :expected, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:meeting_invitees, [:meeting_id, :user_id])
    create index(:meeting_invitees, [:user_id])
  end
end
