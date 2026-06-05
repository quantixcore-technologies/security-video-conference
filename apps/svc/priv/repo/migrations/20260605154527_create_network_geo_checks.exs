defmodule Svc.Repo.Migrations.CreateNetworkGeoChecks do
  use Ecto.Migration

  def change do
    create table(:network_geo_checks) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :ip, :string, null: false
      add :ip_country, :string
      add :is_vpn, :boolean, null: false, default: false
      add :is_proxy, :boolean, null: false, default: false
      add :is_hosting, :boolean, null: false, default: false
      add :decision, :string, null: false
      add :reason, :string
      add :mmdb_version, :string
      add :checked_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:network_geo_checks, [:org_id, :checked_at])
    create index(:network_geo_checks, [:decision])
  end
end
