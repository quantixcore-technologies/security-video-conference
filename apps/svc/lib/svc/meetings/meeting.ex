defmodule Svc.Meetings.Meeting do
  @moduledoc "Видеоконференция (E1). LiveKit room, recording_policy (D-009), анти-захват политика (E5-C)."
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(scheduled ad_hoc)a
  @statuses ~w(planned live ended)a
  @recording_policies ~w(off optional required)a
  # E5-C: реакция на детект захвата экрана
  @capture_reactions ~w(none warn eject)a

  @type t :: %__MODULE__{}

  schema "meetings" do
    field :title, :string
    field :type, Ecto.Enum, values: @types, default: :scheduled
    field :status, Ecto.Enum, values: @statuses, default: :planned
    field :scheduled_start, :utc_datetime_usec
    field :scheduled_end, :utc_datetime_usec
    field :livekit_room_name, :string
    field :recording_policy, Ecto.Enum, values: @recording_policies, default: :off
    # E5-C: пер-встречная анти-захват политика
    field :watermark_enabled, :boolean, default: true
    field :capture_reaction, Ecto.Enum, values: @capture_reactions, default: :none
    field :late_threshold_seconds, :integer, default: 300
    field :recurrence_group, :string

    # S43 — фактическая история: во сколько реально шло, зачем собирались, чем кончилось.
    # scheduled_* — это план; он почти всегда расходится с фактом.
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :purpose, :string
    field :summary, :string

    belongs_to :started_by, Svc.Accounts.User, foreign_key: :started_by_id
    belongs_to :ended_by, Svc.Accounts.User, foreign_key: :ended_by_id
    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :organizer, Svc.Accounts.User, foreign_key: :organizer_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Майлисни очиш: ким очгани ва аниқ вақти ёзилади (S43)."
  def start_changeset(meeting, %Svc.Accounts.User{} = actor) do
    meeting
    |> change(%{status: :live, started_at: DateTime.utc_now(), started_by_id: actor.id})
  end

  @doc """
  Майлисни якунлаш: тугаш вақти, ким ёпгани ва натижа ёзилади.

  `summary` шарт эмас, лекин тарих учун тавсия этилади — кейин «нима учун
  йиғилган эдик» саволига жавоб шу ердан топилади.
  """
  def finish_changeset(meeting, %Svc.Accounts.User{} = actor, attrs \\ %{}) do
    meeting
    |> cast(attrs, [:summary])
    |> validate_length(:summary, max: 4000)
    |> put_change(:status, :ended)
    |> put_change(:ended_at, DateTime.utc_now())
    |> put_change(:ended_by_id, actor.id)
  end

  @doc "Аниқ давомийлиги (сония). Ҳали тугамаган ёки бошланмаган бўлса — nil."
  def duration_seconds(%__MODULE__{started_at: %DateTime{} = s, ended_at: %DateTime{} = e}),
    do: DateTime.diff(e, s)

  def duration_seconds(%__MODULE__{}), do: nil

  def types, do: @types
  def recording_policies, do: @recording_policies
  def capture_reactions, do: @capture_reactions

  def create_changeset(meeting, attrs) do
    meeting
    |> cast(attrs, [
      :org_id,
      :organizer_id,
      :title,
      :type,
      :scheduled_start,
      :scheduled_end,
      :recording_policy,
      :watermark_enabled,
      :capture_reaction,
      :late_threshold_seconds,
      :livekit_room_name,
      :recurrence_group,
      :purpose
    ])
    |> validate_required([:org_id, :organizer_id, :title, :livekit_room_name])
    |> validate_length(:title, min: 2, max: 300)
    |> validate_number(:late_threshold_seconds, greater_than_or_equal_to: 0)
    |> validate_length(:purpose, max: 2000)
    |> validate_schedule()
    |> unique_constraint(:livekit_room_name)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:organizer_id)
  end

  @doc "Редактирование встречи (без org/organizer/room — их менять нельзя)."
  def update_changeset(meeting, attrs) do
    meeting
    |> cast(attrs, [
      :title,
      :type,
      :scheduled_start,
      :scheduled_end,
      :recording_policy,
      :watermark_enabled,
      :capture_reaction,
      :late_threshold_seconds,
      :purpose
    ])
    |> validate_required([:title])
    |> validate_length(:title, min: 2, max: 300)
    |> validate_number(:late_threshold_seconds, greater_than_or_equal_to: 0)
    |> validate_length(:purpose, max: 2000)
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
