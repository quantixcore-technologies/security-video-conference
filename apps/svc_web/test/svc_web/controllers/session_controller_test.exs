defmodule SvcWeb.SessionControllerTest do
  use SvcWeb.ConnCase, async: true

  alias Svc.{Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})

    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "ivan",
        full_name: "Иван Иванов",
        password: "SecurePass123!",
        role: :employee
      })

    %{org: org, user: user}
  end

  test "GET /login рендерит форму входа", %{conn: conn} do
    assert get(conn, ~p"/login") |> html_response(200) =~ "Вход в систему"
  end

  test "POST /login с верным паролем (без 2FA) → /admin + сессия", %{conn: conn} do
    conn = post(conn, ~p"/login", user: %{username: "ivan", password: "SecurePass123!"})
    assert redirected_to(conn) == ~p"/admin"
    assert get_session(conn, :user_id)
  end

  test "POST /login с неверным паролем → ошибка, без сессии", %{conn: conn} do
    conn = post(conn, ~p"/login", user: %{username: "ivan", password: "WrongPassword1"})
    assert html_response(conn, 200) =~ "Неверный логин или пароль"
    refute get_session(conn, :user_id)
  end

  test "POST /login с включённой 2FA → шаг TOTP (без полной сессии)", %{conn: conn, user: user} do
    {user, secret, _uri} = Accounts.setup_totp(user)
    {:ok, _} = Accounts.confirm_totp(user, NimbleTOTP.verification_code(secret))

    conn = post(conn, ~p"/login", user: %{username: "ivan", password: "SecurePass123!"})
    assert redirected_to(conn) == ~p"/login/totp"
    assert get_session(conn, :pending_user_id) == user.id
    refute get_session(conn, :user_id)
  end

  test "DELETE /logout очищает сессию", %{conn: conn, user: user} do
    conn =
      conn
      |> init_test_session(%{user_id: user.id, org_id: user.org_id})
      |> delete(~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_id)
  end

  test "GET /admin без аутентификации → /login", %{conn: conn} do
    assert get(conn, ~p"/admin") |> redirected_to() == ~p"/login"
  end
end
