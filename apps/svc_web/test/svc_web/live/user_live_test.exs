defmodule SvcWeb.UserLiveTest do
  use SvcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Svc.{Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, admin} = mk(org, "admin", "Админ Адмов", :admin_hr)
    {:ok, emp} = mk(org, "emp", "Сотрудник Сотов", :employee)
    %{org: org, admin: admin, emp: emp}
  end

  defp mk(org, username, full_name, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: full_name,
      password: "SecurePass123!",
      role: role
    })
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id, org_id: user.org_id})

  test "неаутентифицированный редиректится на /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/users")
  end

  test "admin/HR видит всех сотрудников и кнопку создания", %{conn: conn, admin: admin} do
    {:ok, _lv, html} = conn |> login(admin) |> live(~p"/admin/users")
    assert html =~ "Админ Адмов"
    assert html =~ "Сотрудник Сотов"
    assert html =~ "/admin/users/new"
  end

  test "employee видит только себя, без кнопки создания (RBAC, D-007)", %{conn: conn, emp: emp} do
    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/users")
    assert html =~ "Сотрудник Сотов"
    refute html =~ "Админ Адмов"
    refute html =~ "/admin/users/new"
  end

  test "employee не может открыть форму создания", %{conn: conn, emp: emp} do
    assert {:error, {:live_redirect, %{to: "/admin/users"}}} =
             conn |> login(emp) |> live(~p"/admin/users/new")
  end

  test "admin/HR создаёт сотрудника", %{conn: conn, admin: admin} do
    {:ok, lv, _html} = conn |> login(admin) |> live(~p"/admin/users/new")

    lv
    |> form("form",
      user: %{
        full_name: "Новый Сотрудник",
        username: "newbie",
        password: "SecurePass123!",
        role: "employee"
      }
    )
    |> render_submit()

    assert Accounts.get_user_by_username(admin.org_id, "newbie")
  end
end
