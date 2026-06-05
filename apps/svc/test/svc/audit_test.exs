defmodule Svc.AuditTest do
  use Svc.DataCase, async: true

  alias Svc.{Audit, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved"})

    {:ok, actor} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "admin",
        full_name: "Админ",
        password: "SecurePass123!",
        role: :admin_hr
      })

    %{org: org, actor: actor}
  end

  test "log/2 пишет запись", %{org: org} do
    assert {:ok, log} =
             Audit.log(:login_success, org_id: org.id, ip: "10.0.0.1", metadata: %{username: "x"})

    assert log.action == "login_success"
    assert log.ip == "10.0.0.1"
    assert log.metadata == %{username: "x"}
  end

  test "log_action/3 подставляет org_id и actor_id", %{org: org, actor: actor} do
    assert {:ok, log} =
             Audit.log_action(actor, :user_create,
               resource_type: :user, resource_id: 42)

    assert log.org_id == org.id
    assert log.actor_user_id == actor.id
    assert log.resource_type == "user"
    assert log.resource_id == "42"
  end

  test "list_logs/2 — свежие сверху, scoped по org", %{org: org} do
    {:ok, _} = Audit.log(:a, org_id: org.id)
    {:ok, _} = Audit.log(:b, org_id: org.id)

    {:ok, other} = Orgs.create_organization(%{name: "Чужое", slug: "chuzhoe"})
    {:ok, _} = Audit.log(:foreign, org_id: other.id)

    logs = Audit.list_logs(org.id)
    actions = Enum.map(logs, & &1.action)
    assert "b" in actions
    assert "a" in actions
    refute "foreign" in actions
    assert List.first(logs).action == "b", "свежие сверху"
  end

  test "append-only: лог переживает удаление актора (actor_user_id не FK)", %{org: org, actor: actor} do
    {:ok, log} = Audit.log_action(actor, :sensitive_action)
    assert log.actor_user_id == actor.id

    Repo.delete!(actor)

    [persisted] = Audit.list_logs(org.id)
    assert persisted.actor_user_id == actor.id, "лог сохранил actor_user_id после удаления юзера"
  end

  test "схема append-only: нет updated_at", %{org: org} do
    {:ok, log} = Audit.log(:x, org_id: org.id)
    refute Map.has_key?(log, :updated_at)
    assert log.inserted_at
  end
end
