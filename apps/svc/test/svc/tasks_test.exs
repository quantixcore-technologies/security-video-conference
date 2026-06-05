defmodule Svc.TasksTest do
  use Svc.DataCase, async: true

  alias Svc.{Tasks, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, boss} = mk(org, "boss", :manager)
    {:ok, emp} = mk(org, "emp", :employee)
    %{org: org, boss: boss, emp: emp}
  end

  defp mk(org, u, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: u,
      full_name: "User #{u}",
      password: "SecurePass123!",
      role: role
    })
  end

  test "create_task: автор + дефолты (todo/normal)", %{boss: boss, emp: emp} do
    assert {:ok, t} = Tasks.create_task(boss, %{"title" => "Подготовить отчёт", "assignee_id" => emp.id})
    assert t.title == "Подготовить отчёт"
    assert t.creator_id == boss.id
    assert t.assignee_id == emp.id
    assert t.status == :todo
    assert t.priority == :normal
  end

  test "create_task требует title", %{boss: boss} do
    assert {:error, cs} = Tasks.create_task(boss, %{"title" => ""})
    assert errors_on(cs)[:title]
  end

  test "set_status :done проставляет completed_at", %{boss: boss} do
    {:ok, t} = Tasks.create_task(boss, %{"title" => "Задача"})
    assert {:ok, done} = Tasks.set_status(t, :done)
    assert done.status == :done
    assert done.completed_at
  end

  test "возврат из :done сбрасывает completed_at", %{boss: boss} do
    {:ok, t} = Tasks.create_task(boss, %{"title" => "Задача"})
    {:ok, done} = Tasks.set_status(t, :done)
    {:ok, back} = Tasks.set_status(done, :in_progress)
    assert is_nil(back.completed_at)
  end

  test "board группирует по статусу", %{boss: boss} do
    Tasks.create_task(boss, %{"title" => "T1"})
    {:ok, t2} = Tasks.create_task(boss, %{"title" => "T2"})
    Tasks.set_status(t2, :in_progress)
    board = Tasks.board(boss.org_id)
    assert length(board[:todo]) == 1
    assert length(board[:in_progress]) == 1
  end

  test "list_tasks scoped по org (D-005)", %{org: org, boss: boss} do
    Tasks.create_task(boss, %{"title" => "Наша"})
    {:ok, other} = Orgs.create_organization(%{name: "Чужое", slug: "ch"})
    {:ok, ob} = mk(other, "obmgr", :manager)
    Tasks.create_task(ob, %{"title" => "Чужая"})
    assert length(Tasks.list_tasks(org.id)) == 1
  end

  test "open_count_for считает незавершённые исполнителя", %{boss: boss, emp: emp} do
    Tasks.create_task(boss, %{"title" => "T1", "assignee_id" => emp.id})
    {:ok, t2} = Tasks.create_task(boss, %{"title" => "T2", "assignee_id" => emp.id})
    Tasks.set_status(t2, :done)
    assert Tasks.open_count_for(emp.id) == 1
  end
end
