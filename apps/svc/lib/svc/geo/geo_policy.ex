defmodule Svc.Geo.GeoPolicy do
  @moduledoc "Гео-политика организации (E7): режим gate, разрешённые страны, whitelist."
  use Ecto.Schema
  import Ecto.Changeset

  @modes ~w(off flag_only enforce)a

  @type t :: %__MODULE__{}

  schema "geo_policies" do
    field :mode, Ecto.Enum, values: @modes, default: :flag_only
    field :allowed_countries, {:array, :string}, default: ["UZ"]
    field :block_vpn, :boolean, default: true
    field :block_proxy, :boolean, default: true
    field :whitelist_ips, {:array, :string}, default: []

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id

    timestamps(type: :utc_datetime_usec)
  end

  def modes, do: @modes

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:org_id, :mode, :allowed_countries, :block_vpn, :block_proxy, :whitelist_ips])
    |> validate_required([:org_id, :mode])
    |> unique_constraint(:org_id)
    |> foreign_key_constraint(:org_id)
  end
end
