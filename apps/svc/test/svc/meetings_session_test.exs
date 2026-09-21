defmodule Svc.MeetingsSessionTest do
  @moduledoc """
  S43 — встречу открывает человек, и закрывает её тот же человек.

  До S43 статус менялся только вебхуком LiveKit, фактическое время нигде не
  оставалось, и «кто собрал совещание» было не восстановить. Требование
  заказчика: открыл — ты же и закрыл, а в истории видно когда, зачем и чем
  кончилось.
  """
  use Svc.DataCase, async: true

  alias Svc.{Meetings, Accounts, Orgs, Attendance}
  alias Svc.Meetings.Meeting

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-s43"})
    {:ok, other_org} = Orgs.create_organization(%{name: "Соседи", slug: "sosed-s43"})
    {:ok, manager} = mk(org, "mgr43", :manager)
    {:ok, employee} = mk(org, "emp43", :employee)
    {:ok, admin} = mk(org, "adm43", :super_admin)

    {:ok, meeting} =
      Meetings.create_meeting(manager, %{title: "Планёрка", purpose: "Отчёт за неделю"})

    %{
      org: org,
      other_org: other_org,
      manager: manager,
      employee: employee,
      admin: admin,
      meeting: meeting
    }
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

  describe "open_meeting/2" do
    test "организатор открывает: статус live, записано кто и когда", %{
      manager: m,
      meeting: meeting
    } do
      before = DateTime.utc_now()
      assert {:ok, opened} = Meetings.open_meeting(m, meeting)

      assert opened.status == :live
      assert opened.started_by_id == m.id
      assert DateTime.compare(opened.started_at, before) != :lt
      assert is_nil(opened.ended_at)
    end

    test "сотрудник открыть не может", %{employee: e, meeting: meeting} do
      assert {:error, :unauthorized} = Meetings.open_meeting(e, meeting)
      assert Repo.get!(Meeting, meeting.id).status == :planned
    end

    test "повторно открыть нельзя", %{manager: m, meeting: meeting} do
      {:ok, opened} = Meetings.open_meeting(m, meeting)
      assert {:error, :already_live} = Meetings.open_meeting(m, opened)
    end

    test "открытие пишется в аудит", %{manager: m, meeting: meeting} do
      {:ok, opened} = Meetings.open_meeting(m, meeting)

      assert Enum.any?(
               Svc.Audit.list_logs(m.org_id),
               &(&1.action == "meeting_open" and &1.resource_id == to_string(opened.id))
             )
    end
  end

  describe "close_meeting/3" do
    setup %{manager: m, meeting: meeting} do
      {:ok, live} = Meetings.open_meeting(m, meeting)
      %{live: live}
    end

    test "закрывает тот, кто открыл: время, автор и итог", %{manager: m, live: live} do
      assert {:ok, closed} = Meetings.close_meeting(m, live, %{summary: "Решили ускорить отчёт"})

      assert closed.status == :ended
      assert closed.ended_by_id == m.id
      assert closed.summary == "Решили ускорить отчёт"
      assert DateTime.compare(closed.ended_at, closed.started_at) != :lt
      assert Meeting.duration_seconds(closed) >= 0
    end

    test "приглашённый сотрудник чужую встречу не закрывает", %{
      employee: e,
      live: live
    } do
      Attendance.add_invitee(live, e)
      assert {:error, :unauthorized} = Meetings.close_meeting(e, live, %{})
      assert Repo.get!(Meeting, live.id).status == :live
    end

    test "super_admin закрывает, если открывший недоступен", %{admin: a, live: live} do
      assert {:ok, closed} = Meetings.close_meeting(a, live, %{})
      assert closed.ended_by_id == a.id
    end

    test "незапущенную встречу закрыть нельзя", %{manager: m} do
      {:ok, fresh} = Meetings.create_meeting(m, %{title: "Ещё не начали"})
      assert {:error, :not_live} = Meetings.close_meeting(m, fresh, %{})
    end

    test "закрытие пишется в аудит с длительностью", %{manager: m, live: live} do
      {:ok, closed} = Meetings.close_meeting(m, live, %{})

      log =
        Svc.Audit.list_logs(m.org_id)
        |> Enum.find(&(&1.action == "meeting_close" and &1.resource_id == to_string(closed.id)))

      assert log
      assert is_integer(log.metadata["duration_seconds"])
    end
  end

  describe "can_close?/2" do
    test "открывший закрывает, даже если он не организатор", %{
      manager: m,
      admin: a,
      meeting: meeting
    } do
      # Открыл админ — значит закрывать в первую очередь ему.
      {:ok, live} = Meetings.open_meeting(a, meeting)
      assert Meetings.can_close?(a, live)

      # Организатор остаётся запасным вариантом (открывший может отвалиться).
      assert Meetings.can_close?(m, live)
    end

    test "посторонний сотрудник — нет", %{employee: e, manager: m, meeting: meeting} do
      {:ok, live} = Meetings.open_meeting(m, meeting)
      refute Meetings.can_close?(e, live)
    end
  end

  describe "history/2" do
    test "показывает только завершённые и только видимые актору", %{
      manager: m,
      employee: e,
      meeting: meeting
    } do
      {:ok, live} = Meetings.open_meeting(m, meeting)
      {:ok, _closed} = Meetings.close_meeting(m, live, %{summary: "Итог"})

      {:ok, running} = Meetings.create_meeting(m, %{title: "Идёт сейчас"})
      {:ok, _} = Meetings.open_meeting(m, running)

      history = Meetings.history(m)
      assert [entry] = history
      assert entry.title == "Планёрка"
      assert entry.purpose == "Отчёт за неделю"
      assert entry.summary == "Итог"
      assert entry.started_by.id == m.id
      assert entry.ended_by.id == m.id

      # Сотрудник, не назначенный на встречу, в истории её не видит (D-016).
      assert Meetings.history(e) == []
    end

    test "limit ограничивает выдачу", %{manager: m} do
      for i <- 1..3 do
        {:ok, meeting} = Meetings.create_meeting(m, %{title: "Встреча #{i}"})
        {:ok, live} = Meetings.open_meeting(m, meeting)
        {:ok, _} = Meetings.close_meeting(m, live, %{})
      end

      assert length(Meetings.history(m, limit: 2)) == 2
    end
  end
end
