defmodule Svc.Repo.Migrations.AddHeadUserFkToDepartments do
  use Ecto.Migration

  def change do
    # head_user_id создан как :bigint в Слайсе 1.1 (users тогда не было). Добавляем FK.
    execute(
      "ALTER TABLE departments ADD CONSTRAINT departments_head_user_id_fkey FOREIGN KEY (head_user_id) REFERENCES users(id) ON DELETE SET NULL",
      "ALTER TABLE departments DROP CONSTRAINT departments_head_user_id_fkey"
    )
  end
end
