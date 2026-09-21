defmodule Svc.Repo.Migrations.AddRejoinGuard do
  @moduledoc """
  S45 — счётчики входов/выходов и отметка подозрения.

  Требование заказчика: участник не может свободно выходить и заходить обратно.
  Первый выход — предупреждение и ещё одна попытка, второй выход — вход закрыт и
  человек берётся «под подозрение». Считать это по одной записи посещаемости было
  нечем: там только joined_at/left_at последнего события.
  """
  use Ecto.Migration

  def change do
    alter table(:attendance_records) do
      add :join_count, :integer, default: 0, null: false
      add :leave_count, :integer, default: 0, null: false

      # Второй выход = отметка для службы безопасности (журнал /admin/security).
      add :flagged, :boolean, default: false, null: false
      add :flagged_at, :utc_datetime_usec
    end
  end
end
