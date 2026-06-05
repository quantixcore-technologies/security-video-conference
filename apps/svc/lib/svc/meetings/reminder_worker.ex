defmodule Svc.Meetings.ReminderWorker do
  @moduledoc """
  Oban-воркер: in-app напоминание участникам о предстоящей встрече (E3).
  Планируется на T-24ч и T-1ч от начала. Идемпотентен (unique по meeting+kind),
  устойчив к ретраям; завершённую встречу пропускает.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:meeting_id, :kind]]

  import Ecto.Query
  alias Svc.{Meetings, Attendance, Notifications, Repo}
  alias Svc.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"meeting_id" => mid, "org_id" => org_id, "kind" => kind}}) do
    meeting = Meetings.get_meeting!(org_id, mid)

    if meeting.status == :ended do
      :ok
    else
      user_ids = meeting.id |> Attendance.list_invitees() |> Enum.map(& &1.user_id)
      users = Repo.all(from u in User, where: u.id in ^user_ids)
      Notifications.notify_many(users, :reminder, reminder_title(kind, meeting), meeting_id: meeting.id)
      :ok
    end
  rescue
    # встреча удалена между постановкой и выполнением — напоминать нечего
    Ecto.NoResultsError -> :ok
  end

  defp reminder_title("24h", m), do: "Завтра встреча: #{m.title}"
  defp reminder_title("1h", m), do: "Через час встреча: #{m.title}"
  defp reminder_title(_, m), do: "Напоминание о встрече: #{m.title}"
end
