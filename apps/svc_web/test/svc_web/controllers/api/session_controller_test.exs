defmodule SvcWeb.API.SessionControllerTest do
  use SvcWeb.ConnCase, async: true

  alias Svc.{Meetings, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})

    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "admin",
        full_name: "Админ Тест",
        password: "SecurePass123!",
        role: :manager
      })

    {:ok, meeting} = Meetings.create_meeting(user, %{title: "Совещание"})
    %{org: org, user: user, meeting: meeting}
  end

  test "POST /api/login → bearer-токен + данные пользователя", %{conn: conn} do
    conn = post(conn, ~p"/api/login", %{username: "admin", password: "SecurePass123!"})
    body = json_response(conn, 200)
    assert is_binary(body["token"])
    assert body["user"]["username"] == "admin"
    assert body["user"]["full_name"] == "Админ Тест"
  end

  test "POST /api/login с неверным паролем → 401", %{conn: conn} do
    conn = post(conn, ~p"/api/login", %{username: "admin", password: "wrong"})
    assert json_response(conn, 401)["error"] == "invalid_credentials"
  end

  test "POST /api/login без полей → 400", %{conn: conn} do
    conn = post(conn, ~p"/api/login", %{})
    assert json_response(conn, 400)["error"] == "username_password_required"
  end

  test "bearer-токен из /api/login открывает защищённый API (join)", %{
    conn: conn,
    meeting: meeting
  } do
    token =
      build_conn()
      |> post(~p"/api/login", %{username: "admin", password: "SecurePass123!"})
      |> json_response(200)
      |> Map.fetch!("token")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/api/meetings/#{meeting.id}/join")

    body = json_response(conn, 200)
    assert is_binary(body["token"])
    assert body["room"] == meeting.livekit_room_name
  end

  test "неверный bearer-токен → 401", %{conn: conn, meeting: meeting} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer garbage")
      |> post(~p"/api/meetings/#{meeting.id}/join")

    assert json_response(conn, 401)["error"] == "unauthorized"
  end
end
