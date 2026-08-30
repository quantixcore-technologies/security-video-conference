defmodule SvcWeb.TaskLiveTest do
  use SvcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Svc.{Tasks, Accounts, Orgs}

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
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/tasks")
  end

  test "manager видит доску с 4 колонками + кнопку создания", %{conn: conn, mgr: mgr} do
    {:ok, _lv, html} = conn |> login(mgr) |> live(~p"/admin/tasks")
    assert html =~ "Новые"
    assert html =~ "В работе"
    assert html =~ "Проверка"
    assert html =~ "Выполнено"
    assert html =~ "/admin/tasks/new"
  end

  test "карточки попадают в колонки по статусу", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, _t1} =
      Tasks.create_task(mgr, %{"title" => "Подготовить отчёт", "assignee_id" => emp.id})

    {:ok, t2} = Tasks.create_task(mgr, %{"title" => "Согласовать бюджет"})
    {:ok, _} = Tasks.set_status(t2, :in_progress)

    {:ok, _lv, html} = conn |> login(mgr) |> live(~p"/admin/tasks")
    assert html =~ "Подготовить отчёт"
    assert html =~ "Согласовать бюджет"
  end

  test "employee не видит кнопку создания и не может открыть /new", %{conn: conn, emp: emp} do
    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/tasks")
    refute html =~ "/admin/tasks/new"

    assert {:error, {:live_redirect, %{to: "/admin/tasks"}}} =
             conn |> login(emp) |> live(~p"/admin/tasks/new")
  end

  test "employee видит только свои задачи (как исполнитель)", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, _mine} = Tasks.create_task(mgr, %{"title" => "Моя задача", "assignee_id" => emp.id})
    {:ok, _foreign} = Tasks.create_task(mgr, %{"title" => "Чужая задача"})

    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/tasks")
    assert html =~ "Моя задача"
    refute html =~ "Чужая задача"
  end

  test "manager создаёт поручение с исполнителем", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, lv, _html} = conn |> login(mgr) |> live(~p"/admin/tasks/new")

    lv
    |> form("form",
      task: %{
        title: "Планёрка отдела",
        priority: "high",
        assignee_id: to_string(emp.id)
      }
    )
    |> render_submit()

    task = Tasks.list_tasks(mgr.org_id) |> Enum.find(&(&1.title == "Планёрка отдела"))
    assert task
    assert task.priority == :high
    assert task.assignee_id == emp.id
    assert task.creator_id == mgr.id
  end

  test "manager двигает карточку (drag-drop → move_task)", %{conn: conn, mgr: mgr} do
    {:ok, t} = Tasks.create_task(mgr, %{"title" => "Двигаемая"})
    assert t.status == :todo

    {:ok, lv, _html} = conn |> login(mgr) |> live(~p"/admin/tasks")

    lv
    |> element("#kanban-board")
    |> render_hook("move_task", %{"id" => to_string(t.id), "status" => "in_progress"})

    assert Tasks.get_task!(mgr.org_id, t.id).status == :in_progress
  end

  test "employee не может двигать карточки", %{conn: conn, mgr: mgr, emp: emp} do
    {:ok, t} = Tasks.create_task(mgr, %{"title" => "Задача", "assignee_id" => emp.id})

    {:ok, lv, _html} = conn |> login(emp) |> live(~p"/admin/tasks")

    lv
    |> element("#kanban-board")
    |> render_hook("move_task", %{"id" => to_string(t.id), "status" => "done"})

    # статус не изменился — у employee нет прав двигать
    assert Tasks.get_task!(mgr.org_id, t.id).status == :todo
  end

  test "руководитель видит сводку + отчёт по исполнителям (E4-D)", %{
    conn: conn,
    mgr: mgr,
    emp: emp
  } do
    Tasks.create_task(mgr, %{"title" => "Задача", "assignee_id" => emp.id})

    {:ok, _lv, html} = conn |> login(mgr) |> live(~p"/admin/tasks")
    assert html =~ "Всего"
    assert html =~ "Отчёт по исполнителям"
    assert html =~ "Открыто"
  end

  test "employee не видит отчёт по исполнителям", %{conn: conn, mgr: mgr, emp: emp} do
    Tasks.create_task(mgr, %{"title" => "Задача", "assignee_id" => emp.id})

    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/tasks")
    refute html =~ "Отчёт по исполнителям"
  end

  test "дашборд показывает виджет «Мои поручения» (E4-D)", %{conn: conn, mgr: mgr, emp: emp} do
    Tasks.create_task(mgr, %{"title" => "Моя задача", "assignee_id" => emp.id})

    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin")
    assert html =~ "Мои поручения"
  end
end
