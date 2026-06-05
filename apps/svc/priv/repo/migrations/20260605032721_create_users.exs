defmodule Svc.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :department_id, references(:departments, on_delete: :nilify_all)

      add :username, :citext, null: false
      add :hashed_password, :string, null: false

      # Профиль (ТЗ: Фото/ФИО/Номер)
      add :full_name, :string, null: false
      add :phone, :string
      add :photo_path, :string

      # RBAC (D-007)
      add :role, :string, null: false, default: "employee"

      # 2FA TOTP (D-006). TODO: app-level шифрование totp_secret (Cloak) — слой хардненинга
      add :totp_secret, :binary
      add :totp_enabled, :boolean, null: false, default: false

      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime_usec
      add :failed_attempts, :integer, null: false, default: 0
      add :locked_until, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:org_id, :username])
    create index(:users, [:org_id, :department_id])
    create index(:users, [:org_id, :role])
  end
end
