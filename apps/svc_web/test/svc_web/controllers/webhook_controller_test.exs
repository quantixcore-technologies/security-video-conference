defmodule SvcWeb.WebhookControllerTest do
  use SvcWeb.ConnCase, async: true

  alias Svc.{Meetings, Accounts, Orgs, Audit}

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
    %{org: org, meeting: meeting}
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
end
