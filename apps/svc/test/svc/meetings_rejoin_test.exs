defmodule Svc.MeetingsRejoinTest do
  @moduledoc """
  S45 — «вышел из звонка → обратно уже не так просто».

  Требование заказчика: участник не может свободно выходить и возвращаться.
  Первый выход — предупреждение и ещё одна попытка. Второй выход — вход закрыт,
  человек берётся под подозрение (журнал безопасности + уведомление организатору).

  Считаем именно ВЫХОДЫ из вебхука `participant_left`, а не выданные токены:
  токен можно взять и не подключиться, а обрыв связи наказывать нечестно.
  """
  use Svc.DataCase, async: true

  alias Svc.{Meetings, Accounts, Orgs, Attendance, AntiCapture, Notifications}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-s45"})
    {:ok, manager} = mk(org, "mgr45", :manager)
    {:ok, emp} = mk(org, "emp45", :employee)

    {:ok, meeting} = Meetings.create_meeting(manager, %{title: "Планёрка"})
    {:ok, _} = Attendance.add_invitee(meeting, emp)
    {:ok, live} = Meetings.open_meeting(manager, meeting)

    %{org: org, manager: manager, emp: emp, meeting: live}
  end

  defp mk(org, username, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: role
    })
  end

  defp join(meeting, user), do: Attendance.record_join(meeting, user.id, DateTime.utc_now())
  defp leave(meeting, user), do: Attendance.record_leave(meeting, user.id, DateTime.utc_now())

  describe "join_guard/2" do
    test "первый вход — без ограничений", %{emp: emp, meeting: m} do
      assert :ok = Meetings.join_guard(emp, m)
    end

    test "пока участник в комнате, переподключение не считается возвратом", %{
      emp: emp,
      meeting: m
    } do
      join(m, emp)
      assert :ok = Meetings.join_guard(emp, m)
    end

    test "после первого выхода — предупреждение, но вход разрешён", %{emp: emp, meeting: m} do
      join(m, emp)
      leave(m, emp)

      assert {:warn, :last_attempt} = Meetings.join_guard(emp, m)
    end

    test "после второго выхода вход закрыт", %{emp: emp, meeting: m} do
      join(m, emp)
      leave(m, emp)
      join(m, emp)
      leave(m, emp)

      assert {:blocked, :rejoin_blocked} = Meetings.join_guard(emp, m)
    end

    test "ведущего не блокируем — иначе встречу некому завершить", %{
      manager: mgr,
      meeting: m
    } do
      join(m, mgr)
      leave(m, mgr)
      join(m, mgr)
      leave(m, mgr)

      assert :ok = Meetings.join_guard(mgr, m)
    end
  end

  describe "второй выход берёт под подозрение" do
    setup %{emp: emp, meeting: m} do
      join(m, emp)
      leave(m, emp)
      join(m, emp)
      leave(m, emp)
      {:blocked, _} = Meetings.join_guard(emp, m)
      :ok
    end

    test "запись посещаемости помечена", %{emp: emp, meeting: m} do
      assert [record] = Attendance.flagged_records(m.id)
      assert record.user_id == emp.id
      assert record.flagged
      assert record.flagged_at
      assert record.leave_count == 2
    end

    test "событие попадает в журнал безопасности", %{org: org, emp: emp, meeting: m} do
      event = org.id |> AntiCapture.list_events() |> Enum.find(&(&1.kind == :rejoin_blocked))

      assert event
      assert event.user_id == emp.id
      assert event.meeting_id == m.id
      assert event.severity == :warning
    end

    test "организатор получает уведомление", %{manager: mgr, emp: emp} do
      assert [note] = Notifications.list_for_user(mgr.id)
      assert note.title =~ emp.full_name
      assert note.body =~ "ikkinchi marta"
    end

    test "повторная проверка не плодит дубликаты отметки", %{emp: emp, meeting: m, org: org} do
      {:blocked, _} = Meetings.join_guard(emp, m)

      assert length(Attendance.flagged_records(m.id)) == 1

      # событий будет два — журнал безопасности фиксирует каждую попытку входа
      assert org.id |> AntiCapture.list_events() |> Enum.count(&(&1.kind == :rejoin_blocked)) == 2
    end
  end

  describe "list_active_meetings/1" do
    test "завершённых в списке нет — они в истории", %{manager: mgr, meeting: m} do
      assert [_] = Meetings.list_active_meetings(mgr)

      {:ok, _} = Meetings.close_meeting(mgr, m, %{})

      assert Meetings.list_active_meetings(mgr) == []
      assert [_] = Meetings.history(mgr)
    end

    test "запланированные и идущие показываются", %{manager: mgr} do
      {:ok, planned} = Meetings.create_meeting(mgr, %{title: "Завтра"})

      titles = mgr |> Meetings.list_active_meetings() |> Enum.map(& &1.title)
      assert "Планёрка" in titles
      assert planned.title in titles
    end
  end
end
