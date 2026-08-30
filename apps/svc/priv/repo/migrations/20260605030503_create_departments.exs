defmodule Svc.Repo.Migrations.CreateDepartments do
  use Ecto.Migration

  def change do
    create table(:departments) do
      add :org_id, references(:organizations, on_delete: :delete_all), null: false

      # self-ref иерархия (ведомство→управление→отдел) — D-007
      add :parent_id, references(:departments, on_delete: :nilify_all)
      add :name, :string, null: false
      # FK на users добавим в Слайс 1.2 (таблицы users ещё нет)
      add :head_user_id, :bigint

      timestamps(type: :utc_datetime_usec)
    end

    create index(:departments, [:org_id])
    create index(:departments, [:parent_id])
  end
end
