defmodule Svc.Repo.Migrations.AddRsvpToInvitees do
  use Ecto.Migration

  def change do
    alter table(:meeting_invitees) do
      add :rsvp_status, :string, null: false, default: "pending"
      add :rsvp_at, :utc_datetime_usec
    end
  end
end
