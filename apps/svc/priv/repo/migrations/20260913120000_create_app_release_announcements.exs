defmodule Svc.Repo.Migrations.CreateAppReleaseAnnouncements do
  use Ecto.Migration

  # D-020: реестр объявленных релизов приложения — «одно уведомление на версию».
  # Таблица развёртывания, без org_id (осознанное исключение из D-005): APK общий
  # для всего сервера, а не для организации.
  def change do
    create table(:app_release_announcements) do
      add :platform, :string, null: false
      add :version_code, :integer, null: false
      add :version_name, :string
      add :notified_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:app_release_announcements, [:platform, :version_code])
  end
end
