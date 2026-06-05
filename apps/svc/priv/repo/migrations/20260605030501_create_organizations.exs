defmodule Svc.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    # citext для case-insensitive уникальности (slug орг, позже username) — E0
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :citext, null: false
      add :settings, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])
  end
end
