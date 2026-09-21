defmodule Svc.Attendance do
  @moduledoc """
  Контекст посещаемости (E2, D-008). Гибрид: запланированные (ростер + авто-статусы)
  + ad-hoc (факт-лог). Записи строятся из LiveKit-вебхуков (E1).
  Расчёт статусов: present / late / left_early / absent.
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Attendance.{Invitee, Record}
  alias Svc.Meetings.Meeting
  alias Svc.Accounts.User

  ## Ростер

  def add_invitee(%Meeting{} = meeting, %User{} = user, expected \\ true) do
    %Invitee{}
    |> Invitee.changeset(%{
      org_id: meeting.org_id,
      meeting_id: meeting.id,
      user_id: user.id,
      expected: expected
    })
    |> Repo.insert(
      on_conflict: [set: [expected: expected]],
      conflict_target: [:meeting_id, :user_id]
    )
  end

  def list_invitees(meeting_id) do
    Repo.all(from i in Invitee, where: i.meeting_id == ^meeting_id)
  end

  @doc "Ростер с предзагруженными пользователями (для RSVP-UI), по имени."
  def list_invitees_with_users(meeting_id) do
    Repo.all(
      from i in Invitee,
        where: i.meeting_id == ^meeting_id,
        join: u in assoc(i, :user),
        preload: [user: u],
        order_by: u.full_name
    )
  end

  @doc """
  Приглашённые, которые ещё НЕ заходили в звонок (S44).

  Именно их зовут кнопкой «позвать на встречу»: тот, кто уже в комнате,
  уведомление получать не должен. Опаздывающий по определению тот, у кого
  нет записи посещаемости со временем входа.
  """
  def pending_invitees(meeting_id) do
    joined =
      from r in Record,
        where: r.meeting_id == ^meeting_id and not is_nil(r.joined_at),
        select: r.user_id

    Repo.all(
      from i in Invitee,
        where: i.meeting_id == ^meeting_id and i.user_id not in subquery(joined),
        join: u in assoc(i, :user),
        preload: [user: u],
        order_by: u.full_name
    )
  end

  @doc "Приглашение конкретного пользователя на встречу (или nil)."
  def get_invitee(meeting_id, user_id) do
    Repo.get_by(Invitee, meeting_id: meeting_id, user_id: user_id)
  end

  @doc "Фиксирует RSVP-ответ (accepted|declined|tentative). {:error, :not_invited} если не в ростере."
  def set_rsvp(meeting_id, user_id, status) do
    case get_invitee(meeting_id, user_id) do
      nil -> {:error, :not_invited}
      invitee -> invitee |> Invitee.rsvp_changeset(status) |> Repo.update()
    end
  end

  ## Записи из вебхуков

  @doc "Вход участника (webhook participant_joined). Идемпотентно по (meeting,user)."
  def record_join(%Meeting{} = meeting, user_id, joined_at) do
    status = join_status(meeting, joined_at)

    %Record{}
    |> Record.changeset(%{
      org_id: meeting.org_id,
      meeting_id: meeting.id,
      user_id: user_id,
      status: status,
      joined_at: joined_at,
      join_count: 1,
      source: :livekit_webhook
    })
    |> Repo.insert(
      on_conflict: [set: [joined_at: joined_at, status: status], inc: [join_count: 1]],
      conflict_target: [:meeting_id, :user_id]
    )
  end

  @doc "Выход (webhook participant_left): left_at, total_seconds += длительность, left_early."
  def record_leave(%Meeting{} = meeting, user_id, left_at) do
    case Repo.get_by(Record, meeting_id: meeting.id, user_id: user_id) do
      nil ->
        {:error, :no_join_record}

      %Record{} = record ->
        secs = (record.total_seconds || 0) + duration(record.joined_at, left_at)
        status = maybe_left_early(meeting, record.status, left_at)

        record
        |> Record.changeset(%{
          left_at: left_at,
          total_seconds: secs,
          status: status,
          leave_count: (record.leave_count || 0) + 1
        })
        |> Repo.update()
    end
  end

  @max_joins 2

  @doc """
  Можно ли участнику (пере)войти в звонок — S45.

  Правило заказчика: вышел один раз — предупреждение и ещё одна попытка;
  вышел второй раз — вход закрыт, человек под подозрением.

  Возвращает:
    * `:ok` — первый вход или он всё ещё в комнате (переподключение внутри сессии);
    * `{:warn, :last_attempt}` — это второй и последний вход;
    * `{:blocked, record}` — лимит исчерпан.

  Считаем именно ВЫХОДЫ (`leave_count` из вебхука `participant_left`), а не выданные
  токены: токен можно взять и не подключиться, а обрыв связи не должен наказывать.
  """
  def rejoin_state(meeting_id, user_id) do
    case Repo.get_by(Record, meeting_id: meeting_id, user_id: user_id) do
      nil ->
        :ok

      %Record{} = record ->
        cond do
          # ещё в комнате: выхода не было или последний вход новее выхода
          still_inside?(record) -> :ok
          record.leave_count >= @max_joins -> {:blocked, record}
          record.leave_count == 1 -> {:warn, :last_attempt}
          true -> :ok
        end
    end
  end

  defp still_inside?(%Record{left_at: nil}), do: true

  defp still_inside?(%Record{joined_at: nil}), do: false

  defp still_inside?(%Record{joined_at: j, left_at: l}), do: DateTime.compare(j, l) == :gt

  @doc "Берёт участника под подозрение (2-й выход). Идемпотентно."
  def flag_suspicious(meeting_id, user_id) do
    case Repo.get_by(Record, meeting_id: meeting_id, user_id: user_id) do
      nil ->
        {:error, :no_record}

      %Record{flagged: true} = record ->
        {:ok, record}

      %Record{} = record ->
        record
        |> Record.changeset(%{flagged: true, flagged_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc "Участники встречи, взятые под подозрение (для журнала и карточки встречи)."
  def flagged_records(meeting_id) do
    Repo.all(
      from r in Record,
        where: r.meeting_id == ^meeting_id and r.flagged == true,
        preload: [:user]
    )
  end

  @doc """
  Помечает absent приглашённых (expected), которые не вошли. Идемпотентно.
  Вызывается Oban-воркером при room_finished (D-008). Ad-hoc встречи — нет absent.
  """
  def finalize_absent(%Meeting{} = meeting) do
    joined_ids =
      Repo.all(from r in Record, where: r.meeting_id == ^meeting.id, select: r.user_id)

    absent_invitees =
      Repo.all(
        from i in Invitee,
          where:
            i.meeting_id == ^meeting.id and i.expected == true and
              i.user_id not in ^joined_ids
      )

    Enum.each(absent_invitees, fn inv ->
      %Record{}
      |> Record.changeset(%{
        org_id: meeting.org_id,
        meeting_id: meeting.id,
        user_id: inv.user_id,
        status: :absent,
        source: :livekit_webhook
      })
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:meeting_id, :user_id])
    end)

    :ok
  end

  def list_attendance(meeting_id) do
    Repo.all(from r in Record, where: r.meeting_id == ^meeting_id, preload: [:user])
  end

  ## Расчёт статусов

  # ad-hoc (нет расписания) → всегда present
  defp join_status(%Meeting{scheduled_start: nil}, _joined_at), do: :present

  defp join_status(%Meeting{scheduled_start: start, late_threshold_seconds: thr}, joined_at) do
    deadline = DateTime.add(start, thr || 0, :second)
    if DateTime.compare(joined_at, deadline) == :gt, do: :late, else: :present
  end

  defp maybe_left_early(%Meeting{scheduled_end: nil}, status, _left_at), do: status

  defp maybe_left_early(%Meeting{scheduled_end: finish}, status, left_at) do
    if status in [:present, :late] and DateTime.compare(left_at, finish) == :lt do
      :left_early
    else
      status
    end
  end

  defp duration(nil, _left), do: 0
  defp duration(joined, left), do: max(DateTime.diff(left, joined, :second), 0)
end
