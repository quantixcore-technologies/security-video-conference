defmodule Svc.LiveKitTest do
  # async: false — тест not_configured меняет Application env
  use Svc.DataCase, async: false

  alias Svc.{LiveKit, Meetings, Accounts, Orgs}

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
    %{org: org, user: mgr, meeting: meeting}
  end

  defp decode_claims(jwt) do
    [_header, payload, _sig] = String.split(jwt, ".")
    payload |> Base.url_decode64!(padding: false) |> Jason.decode!()
  end

  test "join_token генерит JWT с корректными claims", %{user: user, meeting: meeting} do
    assert {:ok, jwt} = LiveKit.join_token(user, meeting)
    assert is_binary(jwt)

    claims = decode_claims(jwt)
    assert claims["sub"] == "user-#{user.id}"
    assert claims["iss"] == "devkey"
    assert claims["video"]["room"] == meeting.livekit_room_name
    assert claims["video"]["roomJoin"] == true
    assert claims["video"]["canPublish"] == true
    assert claims["video"]["canSubscribe"] == true
  end

  test "join_token уважает can_publish: false (например, зритель)", %{
    user: user,
    meeting: meeting
  } do
    {:ok, jwt} = LiveKit.join_token(user, meeting, can_publish: false)
    assert decode_claims(jwt)["video"]["canPublish"] == false
  end

  test "identity/1 стабильна", %{user: user} do
    assert LiveKit.identity(user) == "user-#{user.id}"
  end

  test "{:error, :not_configured} если ключи не заданы", %{user: user, meeting: meeting} do
    old = Application.get_env(:svc, Svc.LiveKit)
    Application.put_env(:svc, Svc.LiveKit, [])
    on_exit(fn -> Application.put_env(:svc, Svc.LiveKit, old) end)

    assert {:error, :not_configured} = LiveKit.join_token(user, meeting)
  end
end
