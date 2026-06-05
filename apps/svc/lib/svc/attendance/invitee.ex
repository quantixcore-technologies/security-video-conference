defmodule Svc.Attendance.Invitee do
  @moduledoc "Приглашённый на встречу (ростер, D-008)."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "meeting_invitees" do
    field :expected, :boolean, default: true

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :meeting, Svc.Meetings.Meeting, foreign_key: :meeting_id
    belongs_to :user, Svc.Accounts.User, foreign_key: :user_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitee, attrs) do
    invitee
    |> cast(attrs, [:org_id, :meeting_id, :user_id, :expected])
    |> validate_required([:org_id, :meeting_id, :user_id])
    |> unique_constraint([:meeting_id, :user_id],
      name: :meeting_invitees_meeting_id_user_id_index
    )
    |> foreign_key_constraint(:meeting_id)
    |> foreign_key_constraint(:user_id)
  end
end
