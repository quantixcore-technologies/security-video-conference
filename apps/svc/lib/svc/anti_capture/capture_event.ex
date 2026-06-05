defmodule Svc.AntiCapture.CaptureEvent do
  @moduledoc "Событие попытки/детекта захвата контента (E5). Append-only журнал, scoped по org_id."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(screenshot_detected recorder_detected screen_record_detected protection_failed)a
  @severities ~w(info warning critical)a

  @type t :: %__MODULE__{}

  schema "capture_events" do
    field :kind, Ecto.Enum, values: @kinds
    field :platform, :string
    field :severity, Ecto.Enum, values: @severities, default: :info
    field :detail, :map, default: %{}
    field :client_session_id, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :meeting, Svc.Meetings.Meeting
    belongs_to :user, Svc.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :org_id, :meeting_id, :user_id, :kind, :platform,
      :severity, :detail, :client_session_id, :occurred_at
    ])
    |> validate_required([:org_id, :kind, :occurred_at])
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:meeting_id)
  end
end
