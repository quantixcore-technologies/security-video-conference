defmodule SvcWeb.WebhookControllerTest do
  use SvcWeb.ConnCase, async: true
  use Oban.Testing, repo: Svc.Repo

  alias Svc.{Meetings, Accounts, Orgs, Audit, Attendance}
  alias Svc.Attendance.FinalizeWorker

  @secret "devsecret_devsecret_devsecret_32x"

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})

    {:ok, mgr} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "mgr",
        full_name: "Менеджер Менеджеров",
        password: "SecurePass123!",
        role: :manager
      })

    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})
    %{org: org, meeting: meeting, organizer: mgr}
  end

  # Валидный webhook-JWT: iss="webhook", подписан api_secret (как делает LiveKit).
  defp webhook_jwt do
    signer = Joken.Signer.create("HS256", @secret)
    {:ok, jwt, _} =
      Joken.encode_and_sign(%{"iss" => "webhook", "exp" => System.os_time(:second) + 60}, signer)

    jwt
  end

  defp post_webhook(conn, body, auth) do
    conn
    |> put_req_header("authorization", auth)
    |> put_req_header("content-type", "application/json")
    |> post(~p"/webhooks/livekit", body)
  end

  test "валидная подпись → 200 + audit-запись", %{conn: conn, org: org, meeting: meeting} do
    body =
      Jason.encode!(%{
        "event" => "participant_joined",
        "room" => %{"name" => meeting.livekit_room_name},
        "participant" => %{"identity" => "user-1"}
      })

    conn = post_webhook(conn, body, "Bearer #{webhook_jwt()}")
    assert response(conn, 200)

    logs = Audit.list_logs(org.id)
    assert Enum.any?(logs, &(&1.action == "livekit.participant_joined"))
  end

  test "невалидная подпись → 401", %{conn: conn} do
    body = Jason.encode!(%{"event" => "room_started"})
    conn = post_webhook(conn, body, "Bearer invalid.token.here")
    assert response(conn, 401)
  end

  test "без Authorization → 401", %{conn: conn} do
    body = Jason.encode!(%{"event" => "room_started"})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/livekit", body)

    assert response(conn, 401)
  end

  test "participant_joined создаёт attendance-запись (E2)", %{
    conn: conn,
    meeting: meeting,
    organizer: user
  } do
    body =
      Jason.encode!(%{
        "event" => "participant_joined",
        "room" => %{"name" => meeting.livekit_room_name},
        "participant" => %{"identity" => "user-#{user.id}"},
        "createdAt" => System.os_time(:second)
      })

    conn = post_webhook(conn, body, "Bearer #{webhook_jwt()}")
    assert response(conn, 200)

    assert [record] = Attendance.list_attendance(meeting.id)
    assert record.user_id == user.id
    assert record.status in [:present, :late]
  end

  test "room_finished ставит FinalizeWorker в очередь (E2)", %{conn: conn, meeting: meeting} do
    body =
      Jason.encode!(%{
        "event" => "room_finished",
        "room" => %{"name" => meeting.livekit_room_name}
      })

    conn = post_webhook(conn, body, "Bearer #{webhook_jwt()}")
    assert response(conn, 200)

    assert_enqueued(
      worker: FinalizeWorker,
      args: %{"meeting_id" => meeting.id, "org_id" => meeting.org_id}
    )
  end
end
