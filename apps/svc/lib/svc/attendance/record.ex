defmodule Svc.Attendance.Record do
  @moduledoc "Запись посещаемости (журнал, D-008). Статусы present/late/left_early/absent."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(present late left_early absent)a
  @sources ~w(livekit_webhook manual)a

  @type t :: %__MODULE__{}

  schema "attendance_records" do
    field :status, Ecto.Enum, values: @statuses
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :total_seconds, :integer, default: 0
    field :source, Ecto.Enum, values: @sources, default: :livekit_webhook

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :meeting, Svc.Meetings.Meeting, foreign_key: :meeting_id
    belongs_to :user, Svc.Accounts.User, foreign_key: :user_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :org_id, :meeting_id, :user_id, :status,
      :joined_at, :left_at, :total_seconds, :source
    ])
    |> validate_required([:org_id, :meeting_id, :user_id, :status])
    |> unique_constraint([:meeting_id, :user_id],
      name: :attendance_records_meeting_id_user_id_index
    )
    |> foreign_key_constraint(:meeting_id)
    |> foreign_key_constraint(:user_id)
  end
end
