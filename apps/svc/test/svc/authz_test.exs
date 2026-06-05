defmodule Svc.AuthzTest do
  use Svc.DataCase, async: true

  alias Svc.{Accounts, Authz, Orgs}

  # Иерархия: Ведомство → [Упр.А → Отдел.А1, Упр.Б]
  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved"})
    {:ok, upr_a} = Orgs.create_department(%{org_id: org.id, name: "Управление А"})
    {:ok, otd_a1} = Orgs.create_department(%{org_id: org.id, parent_id: upr_a.id, name: "Отдел А1"})
    {:ok, upr_b} = Orgs.create_department(%{org_id: org.id, name: "Управление Б"})

    admin = mk_user(org, "admin", :admin_hr, nil)
    sec = mk_user(org, "sec", :security_officer, nil)
    mgr_a = mk_user(org, "mgr_a", :manager, upr_a.id)
    emp_a1 = mk_user(org, "emp_a1", :employee, otd_a1.id)
    emp_b = mk_user(org, "emp_b", :employee, upr_b.id)

    %{
      org: org, admin: admin, sec: sec, mgr_a: mgr_a,
      emp_a1: emp_a1, emp_b: emp_b
    }
  end

  defp mk_user(org, username, role, dept_id) do
    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        department_id: dept_id,
        username: username,
        full_name: "User #{username}",
        password: "SecurePass123!",
        role: role
      })

    user
  end

  describe "visible_user_ids/1 — org-wide роли" do
    test "admin_hr видит всех в организации", ctx do
      ids = Authz.visible_user_ids(ctx.admin)
      for u <- [ctx.admin, ctx.sec, ctx.mgr_a, ctx.emp_a1, ctx.emp_b] do
        assert u.id in ids
      end
    end

    test "security_officer видит всех", ctx do
      ids = Authz.visible_user_ids(ctx.sec)
      assert ctx.emp_b.id in ids
      assert ctx.mgr_a.id in ids
    end
  end

  describe "visible_user_ids/1 — manager (department-scoping)" do
    test "manager видит себя и поддерево своего отдела", ctx do
      ids = Authz.visible_user_ids(ctx.mgr_a)
      assert ctx.mgr_a.id in ids
      assert ctx.emp_a1.id in ids, "должен видеть сотрудника вложенного Отдела А1"
    end

    test "manager НЕ видит сотрудника чужого управления", ctx do
      ids = Authz.visible_user_ids(ctx.mgr_a)
      refute ctx.emp_b.id in ids, "не должен видеть Управление Б"
    end
  end

  describe "visible_user_ids/1 — employee" do
    test "employee видит только себя", ctx do
      assert Authz.visible_user_ids(ctx.emp_a1) == [ctx.emp_a1.id]
    end
  end

  describe "can_view_user?/2" do
    test "manager может смотреть подчинённого из поддерева", ctx do
      assert Authz.can_view_user?(ctx.mgr_a, ctx.emp_a1.id)
    end

    test "manager не может смотреть чужого", ctx do
      refute Authz.can_view_user?(ctx.mgr_a, ctx.emp_b.id)
    end

    test "employee не может смотреть коллегу", ctx do
      refute Authz.can_view_user?(ctx.emp_a1, ctx.emp_b.id)
    end
  end

  describe "org-изоляция (D-005)" do
    test "actor не видит пользователей другой организации", ctx do
      {:ok, other_org} = Orgs.create_organization(%{name: "Чужое", slug: "chuzhoe"})
      foreign = mk_user(other_org, "foreign", :employee, nil)
      refute foreign.id in Authz.visible_user_ids(ctx.admin)
    end
  end
end
