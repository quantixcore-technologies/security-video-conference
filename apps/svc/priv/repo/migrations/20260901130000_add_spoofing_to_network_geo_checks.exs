defmodule Svc.Repo.Migrations.AddSpoofingToNetworkGeoChecks do
  use Ecto.Migration

  # E7-spoofing: детект подмены геолокации (impossible-travel по GPS-истории пользователя).
  def change do
    alter table(:network_geo_checks) do
      add :spoofing, :boolean, null: false, default: false
      add :spoofing_reason, :string
    end
  end
end
