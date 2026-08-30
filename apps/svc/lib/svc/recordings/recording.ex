defmodule Svc.Recordings.Recording do
  @moduledoc "Серверная запись встречи (LiveKit Egress, D-009). Шифрование at-rest (D-010)."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(starting active completed failed)a

  @type t :: %__MODULE__{}

  schema "meeting_recordings" do
    field :egress_id, :string
    field :storage_path, :string
    field :encrypted, :boolean, default: true
    field :status, Ecto.Enum, values: @statuses, default: :starting
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :meeting, Svc.Meetings.Meeting, foreign_key: :meeting_id
    belongs_to :requester, Svc.Accounts.User, foreign_key: :requested_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [
      :org_id,
      :meeting_id,
      :requested_by,
      :egress_id,
      :storage_path,
      :encrypted,
      :status,
      :started_at,
      :ended_at
    ])
    |> validate_required([:org_id, :meeting_id])
    |> unique_constraint(:egress_id)
    |> foreign_key_constraint(:meeting_id)
  end
end
