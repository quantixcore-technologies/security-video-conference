defmodule Svc.Orgs.Department do
  @moduledoc "Отдел/управление/ведомство — иерархия через self-ref (D-007)."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "departments" do
    field :name, :string
    field :head_user_id, :integer

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :parent, Svc.Orgs.Department, foreign_key: :parent_id
    has_many :children, Svc.Orgs.Department, foreign_key: :parent_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(dept, attrs) do
    dept
    |> cast(attrs, [:org_id, :parent_id, :name, :head_user_id])
    |> validate_required([:org_id, :name])
    |> validate_length(:name, min: 2, max: 200)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:parent_id)
  end
end
