defmodule Svc.Meetings.Meeting do
  @moduledoc "Видеоконференция (E1). LiveKit room, recording_policy (D-009)."
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(scheduled ad_hoc)a
  @statuses ~w(planned live ended)a
  @recording_policies ~w(off optional required)a

  @type t :: %__MODULE__{}

  schema "meetings" do
    field :title, :string
    field :type, Ecto.Enum, values: @types, default: :scheduled
    field :status, Ecto.Enum, values: @statuses, default: :planned
    field :scheduled_start, :utc_datetime_usec
    field :scheduled_end, :utc_datetime_usec
    field :livekit_room_name, :string
    field :recording_policy, Ecto.Enum, values: @recording_policies, default: :off
    field :late_threshold_seconds, :integer, default: 300
    field :recurrence_group, :string

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :organizer, Svc.Accounts.User, foreign_key: :organizer_id

    timestamps(type: :utc_datetime_usec)
  end

  def types, do: @types
  def recording_policies, do: @recording_policies

  def create_changeset(meeting, attrs) do
    meeting
    |> cast(attrs, [
      :org_id, :organizer_id, :title, :type, :scheduled_start,
      :scheduled_end, :recording_policy, :late_threshold_seconds, :livekit_room_name,
      :recurrence_group
    ])
    |> validate_required([:org_id, :organizer_id, :title, :livekit_room_name])
    |> validate_length(:title, min: 2, max: 300)
    |> validate_number(:late_threshold_seconds, greater_than_or_equal_to: 0)
    |> validate_schedule()
    |> unique_constraint(:livekit_room_name)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:organizer_id)
  end

  @doc "Редактирование встречи (без org/organizer/room — их менять нельзя)."
  def update_changeset(meeting, attrs) do
    meeting
    |> cast(attrs, [
      :title, :type, :scheduled_start, :scheduled_end,
      :recording_policy, :late_threshold_seconds
    ])
    |> validate_required([:title])
    |> validate_length(:title, min: 2, max: 300)
    |> validate_number(:late_threshold_seconds, greater_than_or_equal_to: 0)
    |> validate_schedule()
  end

  defp validate_schedule(changeset) do
    start = get_field(changeset, :scheduled_start)
    finish = get_field(changeset, :scheduled_end)

    if start && finish && DateTime.compare(finish, start) != :gt do
      add_error(changeset, :scheduled_end, "должно быть позже начала")
    else
      changeset
    end
  end
end
