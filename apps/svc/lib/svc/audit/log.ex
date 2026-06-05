defmodule Svc.Audit.Log do
  @moduledoc "Запись аудита (append-only, D-014). Переживает удаление актора."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    field :ip, :string
    field :user_agent, :string
    field :actor_user_id, :integer

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :org_id, :actor_user_id, :action, :resource_type,
      :resource_id, :metadata, :ip, :user_agent
    ])
    |> validate_required([:action])
  end
end
