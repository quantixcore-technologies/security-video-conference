defmodule SvcWeb.API.CaptureControllerTest do
  @moduledoc """
  E5: HTTP-контракт `/api/capture-events`, на который опираются ТРИ нативных
  клиента — Tauri desktop (S36, Rust-детектор рекордеров), Android и iOS (S34).
  Ломать форму запроса/ответа нельзя без синхронного обновления всех трёх.
  """
  use SvcWeb.ConnCase, async: true

  alias Svc.{Accounts, AntiCapture, Meetings, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-capture"})
    {:ok, manager} = mk(org, "mgr", :manager)
    {:ok, meeting} = Meetings.create_meeting(manager, %{title: "Совещание"})
    %{org: org, user: manager, meeting: meeting}
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

  test "детект рекордера с desktop → 201 + событие с platform и detail", %{
    conn: conn,
    org: org,
    meeting: meeting,
    user: user
  } do
    # Ровно то, что шлёт Tauri-клиент (desktop/src/main.ts → reportRecorders).
    payload = %{
      "kind" => "recorder_detected",
      "platform" => "windows",
      "severity" => "warning",
      "meeting_id" => meeting.id,
      "detail" => %{
        "processes" => [
          %{"name" => "OBS Studio", "process" => "obs64.exe", "pid" => 4242, "category" => "recorder"}
        ]
      }
    }

    body =
      conn
      |> login(user)
      |> post(~p"/api/capture-events", payload)
      |> json_response(201)

    assert body["status"] == "logged"
    assert is_integer(body["id"])
    # Реакция по умолчанию — политика встречи :none.
    assert body["reaction"] == "none"

    assert [event] = AntiCapture.list_for_meeting(meeting.id)
    assert event.kind == :recorder_detected
    assert event.platform == "windows"
    assert event.severity == :warning
    assert event.user_id == user.id
    assert event.org_id == org.id
    assert [%{"name" => "OBS Studio", "pid" => 4242}] = event.detail["processes"]
  end

  test "политика встречи :warn возвращается клиенту в reaction", %{conn: conn, user: user} do
    {:ok, strict} = Meetings.create_meeting(user, %{title: "Строгое", capture_reaction: :warn})

    body =
      conn
      |> login(user)
      |> post(~p"/api/capture-events", %{
        "kind" => "recorder_detected",
        "platform" => "linux",
        "meeting_id" => strict.id
      })
      |> json_response(201)

    # Tauri по этому полю решает: показать баннер (warn) или выйти из звонка (eject).
    assert body["reaction"] == "warn"
  end

  test "без meeting_id событие пишется, реакция — none", %{conn: conn, user: user} do
    body =
      conn
      |> login(user)
      |> post(~p"/api/capture-events", %{"kind" => "recorder_detected", "platform" => "macos"})
      |> json_response(201)

    assert body["reaction"] == "none"
  end

  test "неизвестный kind → 422", %{conn: conn, user: user, meeting: meeting} do
    body =
      conn
      |> login(user)
      |> post(~p"/api/capture-events", %{
        "kind" => "nuke_everything",
        "platform" => "windows",
        "meeting_id" => meeting.id
      })
      |> json_response(422)

    assert body["errors"]["kind"]
  end

  test "401 без аутентификации", %{conn: conn} do
    conn = post(conn, ~p"/api/capture-events", %{"kind" => "recorder_detected"})
    assert json_response(conn, 401)["error"] == "unauthorized"
  end
end
