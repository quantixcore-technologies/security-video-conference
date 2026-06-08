defmodule Svc.Repo.Migrations.AddGpsToNetworkGeoChecks do
  use Ecto.Migration

  # E7: нативный клиент (mobile) присылает GPS-координаты при join.
  # Храним рядом с IP-проверкой для аудита и будущего гео-чека (IP vs GPS country).
  def change do
    alter table(:network_geo_checks) do
      add :gps_lat, :float
      add :gps_lon, :float
      add :gps_accuracy, :float
    end
  end
end
