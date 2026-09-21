defmodule Svc.MeetingsNudgeTest do
  @moduledoc """
  S44 — «позвать на встречу» опаздывающих.

  Требование заказчика: у встречи есть время начала, а тем, кто может
  опоздать, отдельной кнопкой уходит уведомление «приходите на встречу».
  Зовём ТОЛЬКО тех, кто ещё не зашёл в звонок: у кого уже открыт клиент,
  лишнее уведомление только мешает.
  """
  use Svc.DataCase, async: true

  alias Svc.{Meetings, Accounts, Orgs, Attendance, Notifications}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-s44"})
    {:ok, manager} = mk(org, "mgr44", :manager)
    {:ok, late} = mk(org, "late44", :employee)
    {:ok, present} = mk(org, "pres44", :employee)

    {:ok, meeting} =
      Meetings.create_meeting(manager, %{
        title: "Планёрка",
        scheduled_start: DateTime.add(DateTime.utc_now(), 600, :second)
      })

    {:ok, _} = Attendance.add_invitee(meeting, late)
    {:ok, _} = Attendance.add_invitee(meeting, present)

    %{org: org, manager: manager, late: late, present: present, meeting: meeting}
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

  defp join(meeting, user) do
    Attendance.record_join(meeting, user.id, DateTime.utc_now())
  end

  describe "pending_invitees/1" do
    test "зашедшего в звонок в списке нет", %{meeting: m, late: late, present: present} do
      assert m.id |> Attendance.pending_invitees() |> length() == 2

      join(m, present)

      assert [only] = Attendance.pending_invitees(m.id)
      assert only.user_id == late.id
    end
  end

  describe "call_participants/3" do
    test "зовёт только тех, кто ещё не в звонке", %{
      manager: mgr,
      meeting: m,
      late: late,
      present: present
    } do
      join(m, present)

      assert {:ok, [called]} = Meetings.call_participants(mgr, m)
      assert called.id == late.id

      assert [note] = Notifications.list_for_user(late.id)
      assert note.kind == :reminder
      assert note.title =~ "Majlisga chaqiruv"
      assert note.body =~ mgr.full_name
      assert note.meeting_id == m.id

      # тот, кто уже в звонке, уведомления не получает
      assert Notifications.list_for_user(present.id) == []
    end

    test "в теле — время начала встречи", %{manager: mgr, meeting: m, late: late} do
      {:ok, _} = Meetings.call_participants(mgr, m)
      [note] = Notifications.list_for_user(late.id)
      assert note.body =~ "boshlanishi"
    end

    test "можно позвать конкретного человека", %{
      manager: mgr,
      meeting: m,
      late: late,
      present: present
    } do
      assert {:ok, [called]} = Meetings.call_participants(mgr, m, user_ids: [to_string(late.id)])
      assert called.id == late.id
      assert Notifications.list_for_user(present.id) == []
    end

    test "рядовой сотрудник звать не может", %{late: late, meeting: m} do
      assert {:error, :unauthorized} = Meetings.call_participants(late, m)
    end

    test "повторный вызов в течение минуты отклоняется", %{manager: mgr, meeting: m} do
      assert {:ok, _} = Meetings.call_participants(mgr, m)
      assert {:error, :too_soon} = Meetings.call_participants(mgr, m)
    end

    test "если все уже в звонке — звать некого", %{
      manager: mgr,
      meeting: m,
      late: late,
      present: present
    } do
      join(m, late)
      join(m, present)

      assert {:error, :nobody_to_call} = Meetings.call_participants(mgr, m)
    end

    test "завершённую встречу не зовут", %{manager: mgr, meeting: m} do
      {:ok, live} = Meetings.open_meeting(mgr, m)
      {:ok, ended} = Meetings.close_meeting(mgr, live, %{})

      assert {:error, :already_ended} = Meetings.call_participants(mgr, ended)
    end

    test "открывший встречу тоже вправе звать", %{org: org, manager: mgr, meeting: m} do
      {:ok, admin} = mk(org, "adm44", :super_admin)
      {:ok, live} = Meetings.open_meeting(admin, m)

      assert {:ok, called} = Meetings.call_participants(admin, live)
      assert length(called) == 2

      # организатор в списке приглашённых не состоит — его не зовём
      refute Enum.any?(called, &(&1.id == mgr.id))
    end

    test "вызов пишется в аудит с числом позванных", %{manager: mgr, meeting: m} do
      {:ok, called} = Meetings.call_participants(mgr, m)

      log =
        Svc.Audit.list_logs(mgr.org_id)
        |> Enum.find(&(&1.action == "meeting_nudge" and &1.resource_id == to_string(m.id)))

      assert log
      assert log.metadata["called"] == length(called)
    end
  end
end
