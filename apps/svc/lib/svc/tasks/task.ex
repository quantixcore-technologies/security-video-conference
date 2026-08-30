defmodule Svc.Tasks.Task do
  @moduledoc "Поручение/задача (E4, D-015). Автор→исполнитель, статус (Kanban), приоритет, дедлайн."
  use Ecto.Schema
  import Ecto.Changeset

  @priorities ~w(low normal high urgent)a
  @statuses ~w(todo in_progress review done cancelled)a

  @type t :: %__MODULE__{}

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :priority, Ecto.Enum, values: @priorities, default: :normal
    field :status, Ecto.Enum, values: @statuses, default: :todo
    field :due_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :creator, Svc.Accounts.User, foreign_key: :creator_id
    belongs_to :assignee, Svc.Accounts.User, foreign_key: :assignee_id
    belongs_to :meeting, Svc.Meetings.Meeting

    timestamps(type: :utc_datetime_usec)
  end

  def priorities, do: @priorities
  def statuses, do: @statuses

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :org_id,
      :creator_id,
      :assignee_id,
      :meeting_id,
      :title,
      :description,
      :priority,
      :status,
      :due_at
    ])
    |> validate_required([:org_id, :title])
    |> validate_length(:title, min: 2, max: 300)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:assignee_id)
    |> foreign_key_constraint(:meeting_id)
    |> maybe_set_completed()
  end

  # completed_at проставляется при переходе в :done, сбрасывается при возврате
  defp maybe_set_completed(changeset) do
    case get_change(changeset, :status) do
      :done ->
        put_change(changeset, :completed_at, DateTime.utc_now())

      s when s in [:todo, :in_progress, :review, :cancelled] ->
        put_change(changeset, :completed_at, nil)

      _ ->
        changeset
    end
  end
end
