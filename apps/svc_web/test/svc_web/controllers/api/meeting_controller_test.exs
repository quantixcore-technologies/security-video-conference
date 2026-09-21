defmodule SvcWeb.API.MeetingControllerTest do
  use SvcWeb.ConnCase, async: true

  alias Svc.{Meetings, Accounts, Orgs, Attendance}

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

  test "D-016: участник ТОЙ ЖЕ орг, но НЕ приглашённый → 404 (не может войти в чужую закрытую встречу)",
       %{conn: conn, org: org, meeting: meeting} do
    {:ok, outsider} = mk(org, "outsider", :employee)
    conn = conn |> login(outsider) |> post(~p"/api/meetings/#{meeting.id}/join")
    assert json_response(conn, 404)["error"] == "meeting_not_found"
  end

  test "D-016: приглашённый участник той же орг → join проходит (200 + токен)",
       %{conn: conn, org: org, meeting: meeting} do
    {:ok, invited} = mk(org, "invited", :employee)
    {:ok, _} = Attendance.add_invitee(meeting, invited)
    conn = conn |> login(invited) |> post(~p"/api/meetings/#{meeting.id}/join")
    assert is_binary(json_response(conn, 200)["token"])
  end

  ## E7 — GPS/гео pre-join gate (нативный клиент)

  test "join с GPS → записывает гео-проверку с координатами", %{
    conn: conn,
    user: user,
    meeting: meeting
  } do
    conn =
      conn
      |> login(user)
      |> post(~p"/api/meetings/#{meeting.id}/join", %{lat: 41.31, lon: 69.28, accuracy: 12.5})

    assert json_response(conn, 200)["room"] == meeting.livekit_room_name

    [check | _] = Svc.Geo.list_checks(user.org_id)
    assert check.meeting_id == meeting.id
    assert check.user_id == user.id
    assert check.gps_lat == 41.31
    assert check.gps_lon == 69.28
    assert check.gps_accuracy == 12.5
    # 127.0.0.1 в тестах → локальная сеть → allow
    assert check.decision == :allow
    assert check.ip_country == "LOCAL"
  end

  test "join без GPS → гео-проверка с nil-координатами, join проходит", %{
    conn: conn,
    user: user,
    meeting: meeting
  } do
    conn = conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/join")
    assert json_response(conn, 200)

    [check | _] = Svc.Geo.list_checks(user.org_id)
    assert is_nil(check.gps_lat)
    assert is_nil(check.gps_lon)
  end

  # ── S43: майлисни очиш/ёпиш ва тарих ──

  describe "open/close (S43)" do
    test "организатор открывает, тот же человек закрывает", %{
      conn: conn,
      user: user,
      meeting: meeting
    } do
      opened =
        conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/open") |> json_response(200)

      assert opened["status"] == "live"
      assert is_binary(opened["started_at"])
      assert opened["can_open"] == false
      assert opened["can_close"] == true

      closed =
        build_conn()
        |> login(user)
        |> post(~p"/api/meetings/#{meeting.id}/close", %{"summary" => "Задачи розданы"})
        |> json_response(200)

      assert closed["status"] == "ended"
      assert closed["summary"] == "Задачи розданы"
      assert is_integer(closed["duration_seconds"])
      assert closed["can_close"] == false
    end

    test "приглашённый сотрудник открыть не может → 403", %{
      conn: conn,
      org: org,
      meeting: meeting
    } do
      {:ok, emp} = mk(org, "emp-open", :employee)
      Attendance.add_invitee(meeting, emp)

      conn = conn |> login(emp) |> post(~p"/api/meetings/#{meeting.id}/open")
      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "повторное открытие → 409", %{conn: conn, user: user, meeting: meeting} do
      {:ok, _} = Meetings.open_meeting(user, meeting)

      conn = conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/open")
      assert json_response(conn, 409)["error"] == "already_live"
    end

    test "чужая встреча → 404, а не 403 (не раскрываем существование)", %{meeting: meeting} do
      {:ok, other_org} = Orgs.create_organization(%{name: "Чужое-43", slug: "ch43"})
      {:ok, other} = mk(other_org, "other43", :manager)

      conn = build_conn() |> login(other) |> post(~p"/api/meetings/#{meeting.id}/open")
      assert json_response(conn, 404)["error"] == "meeting_not_found"
    end

    test "список встреч отдаёт can_open для организатора", %{
      conn: conn,
      user: user
    } do
      body = conn |> login(user) |> get(~p"/api/meetings") |> json_response(200)
      assert [m] = body["meetings"]
      assert m["can_open"] == true
      assert m["can_close"] == false
    end
  end

  describe "history (S43)" do
    test "отдаёт завершённые с временем, поводом и именами", %{
      conn: conn,
      user: user,
      meeting: meeting
    } do
      {:ok, _} = Meetings.update_meeting(meeting, %{purpose: "Квартальный отчёт"})
      meeting = Meetings.get_meeting!(user.org_id, meeting.id)
      {:ok, live} = Meetings.open_meeting(user, meeting)
      {:ok, _} = Meetings.close_meeting(user, live, %{summary: "Отчёт принят"})

      body = conn |> login(user) |> get(~p"/api/meetings/history") |> json_response(200)

      assert [entry] = body["meetings"]
      assert entry["purpose"] == "Квартальный отчёт"
      assert entry["summary"] == "Отчёт принят"
      assert entry["started_by_name"] == user.full_name
      assert entry["ended_by_name"] == user.full_name
      assert is_binary(entry["started_at"])
      assert is_binary(entry["ended_at"])
    end

    test "идущая встреча в историю не попадает", %{conn: conn, user: user, meeting: meeting} do
      {:ok, _} = Meetings.open_meeting(user, meeting)

      body = conn |> login(user) |> get(~p"/api/meetings/history") |> json_response(200)
      assert body["meetings"] == []
    end
  end

  describe "nudge (S44)" do
    test "зовёт неявившихся и отдаёт их число", %{
      conn: conn,
      org: org,
      user: user,
      meeting: meeting
    } do
      {:ok, emp} = mk(org, "late-api", :employee)
      Attendance.add_invitee(meeting, emp)

      body =
        conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/nudge") |> json_response(200)

      assert body["called"] == 1
      assert [%{"full_name" => name}] = body["users"]
      assert name == emp.full_name
      assert [note] = Svc.Notifications.list_for_user(emp.id)
      assert note.title =~ "Majlisga chaqiruv"
    end

    test "повторный вызов подряд → 429", %{conn: conn, org: org, user: user, meeting: meeting} do
      {:ok, emp} = mk(org, "late-429", :employee)
      Attendance.add_invitee(meeting, emp)

      conn |> login(user) |> post(~p"/api/meetings/#{meeting.id}/nudge") |> json_response(200)

      again = build_conn() |> login(user) |> post(~p"/api/meetings/#{meeting.id}/nudge")
      assert json_response(again, 429)["error"] == "too_soon"
    end

    test "приглашённый сотрудник звать не может → 403", %{
      conn: conn,
      org: org,
      meeting: meeting
    } do
      {:ok, emp} = mk(org, "emp-nudge", :employee)
      Attendance.add_invitee(meeting, emp)

      conn = conn |> login(emp) |> post(~p"/api/meetings/#{meeting.id}/nudge")
      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "список встреч показывает, скольких ещё можно позвать", %{
      conn: conn,
      org: org,
      user: user,
      meeting: meeting
    } do
      {:ok, emp} = mk(org, "pending-count", :employee)
      Attendance.add_invitee(meeting, emp)

      body = conn |> login(user) |> get(~p"/api/meetings") |> json_response(200)
      assert [m] = body["meetings"]
      assert m["pending_count"] == 1
    end

    test "создание встречи принимает время начала", %{conn: conn, user: user} do
      body =
        conn
        |> login(user)
        |> post(~p"/api/meetings", %{
          "title" => "Planerka",
          "purpose" => "Hisobot",
          "scheduled_start" => "2026-10-01T09:30"
        })
        |> json_response(201)

      created = Meetings.get_meeting!(user.org_id, body["id"])
      assert created.purpose == "Hisobot"
      assert Calendar.strftime(created.scheduled_start, "%Y-%m-%d %H:%M") == "2026-10-01 09:30"
    end
  end
end
