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

  @max_occurrences 52

  @doc """
  Создаёт серию повторяющихся встреч (E3). freq ∈ "daily"|"weekly", count повторений.
  Каждый экземпляр — обычная встреча с общим `recurrence_group` (напоминания планируются
  для каждой). Требует scheduled_start. Возвращает {:ok, group, [meeting]} | {:error, reason}.
  """
  def create_recurring(%User{} = organizer, attrs, freq, count)
      when freq in ["daily", "weekly"] and is_integer(count) and count > 1 do
    count = min(count, @max_occurrences)
    start = fetch_start(attrs)

    if is_nil(start) do
      {:error, :no_start}
    else
      group = Ecto.UUID.generate()
      duration = duration_seconds(attrs)

      results =
        for i <- 0..(count - 1) do
          inst_start = shift(start, freq, i)

          attrs
          |> Map.put(:scheduled_start, inst_start)
          |> Map.put(:scheduled_end, duration && DateTime.add(inst_start, duration, :second))
          |> Map.put(:recurrence_group, group)
          |> then(&create_meeting(organizer, &1))
        end

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, group, Enum.map(results, fn {:ok, m} -> m end)}
        error -> error
      end
    end
  end

  defp fetch_start(attrs),
    do: Map.get(attrs, :scheduled_start) || Map.get(attrs, "scheduled_start")

  defp duration_seconds(attrs) do
    s = fetch_start(attrs)
    e = Map.get(attrs, :scheduled_end) || Map.get(attrs, "scheduled_end")
    if s && e, do: DateTime.diff(e, s, :second), else: nil
  end

  defp shift(dt, "daily", n), do: DateTime.add(dt, n * 86_400, :second)
  defp shift(dt, "weekly", n), do: DateTime.add(dt, n * 7 * 86_400, :second)

  def get_meeting!(org_id, id), do: Repo.get_by!(Meeting, id: id, org_id: org_id)

  def get_meeting_by_room(room_name) do
    Repo.get_by(Meeting, livekit_room_name: room_name)
  end

  def list_meetings(org_id) do
    Repo.all(from m in Meeting, where: m.org_id == ^org_id, order_by: [desc: m.inserted_at])
  end

  @doc "Встречи с scheduled_start в диапазоне [from, to] — для календаря (E3)."
  def list_in_range(org_id, %DateTime{} = from, %DateTime{} = to) do
    Repo.all(
      from m in Meeting,
        where:
          m.org_id == ^org_id and not is_nil(m.scheduled_start) and
            m.scheduled_start >= ^from and m.scheduled_start <= ^to,
        order_by: m.scheduled_start
    )
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

  @doc """
  Может ли пользователь организовывать/управлять встречами.

  D-015 (2026-09-02, заказчик): организация встреч — ТОЛЬКО роль `:manager`
  (руководитель). Назначает эту роль сотруднику только `:super_admin` (см.
  can_manage_users? в user_live). Разделение обязанностей: кто заводит людей ≠
  кто ведёт встречи.
  """
  def can_organize?(%User{role: role}), do: role == :manager

  # Уникальное имя LiveKit-комнаты (не угадывается).
  defp generate_room_name do
    "room_" <> (:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false))
  end
end
