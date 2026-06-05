defmodule Svc.Orgs.Organization do
  @moduledoc "Организация (корень тенанта, D-005)."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active suspended)a

  @type t :: %__MODULE__{}

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :active

    has_many :departments, Svc.Orgs.Department, foreign_key: :org_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug, :settings, :status])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &String.downcase/1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "только строчные буквы, цифры и дефис")
    |> validate_length(:name, min: 2, max: 200)
    |> unique_constraint(:slug)
  end
end
