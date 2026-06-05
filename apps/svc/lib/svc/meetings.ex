defmodule Svc.Meetings do
  @moduledoc """
  Контекст видеоконференций (E1). Создание/жизненный цикл встреч.
  Организатор — manager/admin (RBAC, D-007). Всё scoped по org_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Meetings.Meeting
  alias Svc.Accounts.User

  @doc "Создаёт встречу от имени организатора (manager/admin/super_admin)."
  def create_meeting(%User{} = organizer, attrs) do
    if can_organize?(organizer) do
      attrs =
        attrs
        |> Map.merge(%{org_id: organizer.org_id, organizer_id: organizer.id})
        |> Map.put_new(:livekit_room_name, generate_room_name())

      case %Meeting{} |> Meeting.create_changeset(attrs) |> Repo.insert() do
        {:ok, meeting} = ok ->
          schedule_reminders(meeting)
          ok

        error ->
          error
      end
    else
      {:error, :unauthorized}
    end
  end

  @reminder_offsets [{"24h", 86_400}, {"1h", 3_600}]

  @doc "Планирует Oban-напоминания (T-24ч, T-1ч) для встречи с scheduled_start."
  def schedule_reminders(%Meeting{scheduled_start: nil}), do: :ok

  def schedule_reminders(%Meeting{} = m) do
    now = DateTime.utc_now()

    Enum.each(@reminder_offsets, fn {kind, sec} ->
      at = DateTime.add(m.scheduled_start, -sec, :second)

      if DateTime.compare(at, now) == :gt do
        %{meeting_id: m.id, org_id: m.org_id, kind: kind}
        |> Svc.Meetings.ReminderWorker.new(scheduled_at: at)
        |> Oban.insert(replace: [scheduled: [:scheduled_at]])
      end
    end)

    :ok
  end

  def get_meeting!(org_id, id), do: Repo.get_by!(Meeting, id: id, org_id: org_id)

  def get_meeting_by_room(room_name) do
    Repo.get_by(Meeting, livekit_room_name: room_name)
  end

  def list_meetings(org_id) do
    Repo.all(from m in Meeting, where: m.org_id == ^org_id, order_by: [desc: m.inserted_at])
  end

  def start_meeting(%Meeting{} = m), do: update_status(m, :live)
  def end_meeting(%Meeting{} = m), do: update_status(m, :ended)

  @doc "Редактирование встречи (название/время/политика записи)."
  def update_meeting(%Meeting{} = m, attrs) do
    case m |> Meeting.update_changeset(attrs) |> Repo.update() do
      {:ok, meeting} = ok ->
        schedule_reminders(meeting)
        ok

      error ->
        error
    end
  end

  @doc "Changeset для формы редактирования встречи (LiveView)."
  def change_meeting(%Meeting{} = m, attrs \\ %{}), do: Meeting.update_changeset(m, attrs)

  defp update_status(meeting, status) do
    meeting |> Ecto.Changeset.change(status: status) |> Repo.update()
  end

  @doc "Может ли пользователь организовывать встречи (D-007)."
  def can_organize?(%User{role: role}), do: role in [:super_admin, :admin_hr, :manager]

  # Уникальное имя LiveKit-комнаты (не угадывается).
  defp generate_room_name do
    "room_" <> (:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false))
  end
end
