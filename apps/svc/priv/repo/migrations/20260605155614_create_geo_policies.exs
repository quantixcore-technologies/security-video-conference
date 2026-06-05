defmodule Svc.Repo.Migrations.CreateGeoPolicies do
  use Ecto.Migration

  def change do
    create table(:geo_policies) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :mode, :string, null: false, default: "flag_only"
      add :allowed_countries, {:array, :string}, null: false, default: ["UZ"]
      add :block_vpn, :boolean, null: false, default: true
      add :block_proxy, :boolean, null: false, default: true
      add :whitelist_ips, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:geo_policies, [:org_id])
  end
end
