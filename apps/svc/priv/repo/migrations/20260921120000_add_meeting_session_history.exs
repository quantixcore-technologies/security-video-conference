defmodule Svc.Repo.Migrations.AddMeetingSessionHistory do
  @moduledoc """
  S43 — майлис тарихи: кто открыл, когда фактически шло и зачем собирались.

  До сих пор у встречи были только ПЛАНОВЫЕ `scheduled_start/end` и статус.
  Фактическое время нигде не сохранялось: после завершения нельзя было сказать,
  во сколько встреча реально началась и сколько шла. Для госучреждения это и есть
  «протокол»: когда собрались, кто открыл, по какому вопросу, чем закончили.

  `started_by_id` — тот, кто открыл встречу. Закрыть её вправе он же (или
  организатор): требование заказчика — встречу закрывает тот, кто её открыл.
  """
  use Ecto.Migration

  def change do
    alter table(:meetings) do
      # Фактическое время (в отличие от scheduled_*)
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :started_by_id, references(:users, on_delete: :nilify_all)
      add :ended_by_id, references(:users, on_delete: :nilify_all)

      # Зачем собирались и чем закончилось — попадает в историю.
      add :purpose, :text
      add :summary, :text
    end

    # (индекс [:org_id, :status] уже создан более ранней миграцией)
  end
end
