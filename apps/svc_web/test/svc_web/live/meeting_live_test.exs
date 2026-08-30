defmodule SvcWeb.MeetingLiveTest do
  use SvcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Svc.{Meetings, Accounts, Orgs, Attendance, Tasks, Notifications}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, dept} = Orgs.create_department(%{org_id: org.id, name: "Отдел"})
    {:ok, mgr} = mk(org, "mgr", :manager, dept.id)
    {:ok, emp} = mk(org, "emp", :employee, dept.id)
    %{org: org, mgr: mgr, emp: emp}
  end

  defp mk(org, username, role, dept) do
    Accounts.create_user(%{
      org_id: org.id,
      department_id: dept,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: role
    })
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id, org_id: user.org_id})

  test "неаутентифицированный → /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/meetings")
  end

  test "manager видит список + кнопку создания", %{conn: conn, mgr: mgr} do
    {:ok, _m} = Meetings.create_meeting(mgr, %{title: "Существующая встреча"})
    {:ok, _lv, html} = conn |> login(mgr) |> live(~p"/admin/meetings")
    assert html =~ "Существующая встреча"
    assert html =~ "/admin/meetings/new"
  end

  test "employee не видит кнопку создания и не может открыть /new", %{conn: conn, emp: emp} do
    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/meetings")
    refute html =~ "/admin/meetings/new"

    assert {:error, {:live_redirect, %{to: "/admin/meetings"}}} =
             conn |> login(emp) |> live(~p"/admin/meetings/new")
  end

  test "manager создаёт встречу с ростером", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, lv, _html} = conn |> login(mgr) |> live(~p"/admin/meetings/new")

    lv
    |> form("form",
      meeting: %{
        title: "Планёрка отдела",
        recording_policy: "optional",
        invitee_ids: [to_string(emp.id)]
      }
    )
    |> render_submit()

    meeting = Meetings.list_meetings(mgr.org_id) |> Enum.find(&(&1.title == "Планёрка отдела"))
    assert meeting
    assert meeting.recording_policy == :optional
    assert [invitee] = Attendance.list_invitees(meeting.id)
    assert invitee.user_id == emp.id
  end

  test "show отображает журнал посещаемости", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})
    {:ok, _} = Attendance.record_join(meeting, emp.id, DateTime.utc_now())

    {:ok, _lv, html} = conn |> login(mgr) |> live(~p"/admin/meetings/#{meeting.id}")
    assert html =~ "Журнал посещаемости"
    assert html =~ emp.full_name
  end

  test "manager ставит поручение по итогам встречи (E4-C)", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})

    {:ok, lv, html} = conn |> login(mgr) |> live(~p"/admin/meetings/#{meeting.id}/assign-task")
    assert html =~ "Поручение по итогам"

    lv
    |> form("form",
      task: %{title: "Подготовить смету", assignee_id: to_string(emp.id), priority: "high"}
    )
    |> render_submit()

    task = Tasks.list_tasks(mgr.org_id) |> Enum.find(&(&1.title == "Подготовить смету"))
    assert task
    assert task.meeting_id == meeting.id
    assert task.assignee_id == emp.id
    assert Notifications.unread_count(emp.id) == 1
  end

  test "employee не может открыть форму поручения из встречи", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})

    assert {:error, {:live_redirect, %{to: path}}} =
             conn |> login(emp) |> live(~p"/admin/meetings/#{meeting.id}/assign-task")

    assert path =~ "/admin/meetings/#{meeting.id}"
  end
end
