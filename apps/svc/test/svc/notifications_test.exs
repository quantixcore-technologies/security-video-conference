defmodule Svc.NotificationsTest do
  use Svc.DataCase, async: true

  alias Svc.{Notifications, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved"})
    {:ok, user} = mk(org, "ivanov")
    %{org: org, user: user}
  end

  defp mk(org, username) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: :employee
    })
  end

  test "notify создаёт непрочитанное уведомление", %{user: user} do
    assert {:ok, n} = Notifications.notify(user, :invite, "Приглашение", body: "тело")
    assert n.kind == :invite
    assert n.title == "Приглашение"
    assert n.body == "тело"
    assert n.user_id == user.id
    assert n.org_id == user.org_id
    assert is_nil(n.read_at)
  end

  test "unread_count считает непрочитанные", %{user: user} do
    Notifications.notify(user, :invite, "1")
    Notifications.notify(user, :reminder, "2")
    assert Notifications.unread_count(user.id) == 2
  end

  test "mark_read отмечает одно и возвращает счётчик", %{user: user} do
    {:ok, n} = Notifications.notify(user, :invite, "1")
    Notifications.notify(user, :reminder, "2")
    assert Notifications.mark_read(user.id, n.id) == 1
    assert Notifications.unread_count(user.id) == 1
  end

  test "mark_all_read обнуляет непрочитанные", %{user: user} do
    Notifications.notify(user, :invite, "1")
    Notifications.notify(user, :reminder, "2")
    assert Notifications.mark_all_read(user.id) == 2
    assert Notifications.unread_count(user.id) == 0
  end

  test "list_for_user — свежие сверху", %{user: user} do
    {:ok, _} = Notifications.notify(user, :invite, "Первое")
    {:ok, _} = Notifications.notify(user, :reminder, "Второе")
    titles = Notifications.list_for_user(user.id) |> Enum.map(& &1.title)
    assert titles == ["Второе", "Первое"]
  end

  test "notify_many рассылает каждому", %{org: org, user: user} do
    {:ok, u2} = mk(org, "petrov")
    Notifications.notify_many([user, u2], :invite, "Всем")
    assert Notifications.unread_count(user.id) == 1
    assert Notifications.unread_count(u2.id) == 1
  end

  test "mark_read scoped по user — чужое не трогает", %{org: org, user: user} do
    {:ok, u2} = mk(org, "petrov")
    {:ok, n} = Notifications.notify(u2, :invite, "Чужое")
    assert Notifications.mark_read(user.id, n.id) == 0
    assert Notifications.unread_count(u2.id) == 1
  end
end
