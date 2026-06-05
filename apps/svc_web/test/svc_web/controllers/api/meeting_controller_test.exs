defmodule SvcWeb.API.MeetingControllerTest do
  use SvcWeb.ConnCase, async: true

  alias Svc.{Meetings, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, mgr} = mk(org, "mgr", :manager)
    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})
    %{org: org, user: mgr, meeting: meeting}
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

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id, org_id: user.org_id})

  test "join → токен + url для аутентифицированного", %{conn: conn, user: user, meeting: meeting} do
    conn = conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/join")
    body = json_response(conn, 200)
    assert is_binary(body["token"])
    assert body["room"] == meeting.livekit_room_name
  end

  test "401 без аутентификации", %{conn: conn, meeting: meeting} do
    conn = post(conn, ~p"/api/meetings/#{meeting.id}/join")
    assert json_response(conn, 401)["error"] == "unauthorized"
  end

  test "404 для несуществующей встречи", %{conn: conn, user: user} do
    conn = conn |> login(user) |> post(~p"/api/meetings/999999/join")
    assert json_response(conn, 404)["error"] == "meeting_not_found"
  end

  test "org-изоляция: чужая встреча → 404 (D-005)", %{conn: conn, meeting: meeting} do
    {:ok, other_org} = Orgs.create_organization(%{name: "Чужое", slug: "ch"})
    {:ok, other_user} = mk(other_org, "other", :manager)

    conn = conn |> login(other_user) |> post(~p"/api/meetings/#{meeting.id}/join")
    assert json_response(conn, 404)
  end
end
