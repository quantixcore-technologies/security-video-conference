defmodule Svc.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all)
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # лента пользователя (свежие сверху) + быстрый счётчик непрочитанных
    create index(:notifications, [:user_id, :inserted_at])
    create index(:notifications, [:user_id, :read_at])
    create index(:notifications, [:org_id])
  end
end
