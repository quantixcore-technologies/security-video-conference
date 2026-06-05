defmodule Svc.Attendance.FinalizeWorker do
  @moduledoc """
  Oban-воркер: при завершении встречи помечает absent приглашённых, не вошедших
  (D-008). Асинхронно и идемпотентно — устойчив к ретраям вебхуков.
  """
  use Oban.Worker, queue: :attendance, max_attempts: 3

  alias Svc.{Meetings, Attendance}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"meeting_id" => meeting_id, "org_id" => org_id}}) do
    meeting = Meetings.get_meeting!(org_id, meeting_id)
    Attendance.finalize_absent(meeting)
    :ok
  rescue
    # встреча удалена между постановкой и выполнением — финализировать нечего
    Ecto.NoResultsError -> :ok
  end
end
