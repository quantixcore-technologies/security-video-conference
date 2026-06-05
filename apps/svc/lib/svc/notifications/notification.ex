defmodule Svc.Notifications.Notification do
  @moduledoc "In-app уведомление (E3). Scoped по org_id + user_id (D-005)."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(invite reminder update cancel)a

  @type t :: %__MODULE__{}

  schema "notifications" do
    field :kind, Ecto.Enum, values: @kinds
    field :title, :string
    field :body, :string
    field :read_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :user, Svc.Accounts.User
    belongs_to :meeting, Svc.Meetings.Meeting

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:org_id, :user_id, :meeting_id, :kind, :title, :body, :read_at])
    |> validate_required([:org_id, :user_id, :kind, :title])
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:meeting_id)
  end
end
