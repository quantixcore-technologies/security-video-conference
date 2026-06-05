defmodule SvcWeb.WebhookController do
  @moduledoc "Приём LiveKit-вебхуков (E1). Проверка подписи → лог. E2 добавит attendance."
  use SvcWeb, :controller
  require Logger

  alias Svc.{LiveKit, Audit, Meetings}

  def livekit(conn, _params) do
    raw_body = conn.private[:raw_body] || ""
    auth = get_req_header(conn, "authorization") |> List.first() || ""

    case LiveKit.verify_webhook(raw_body, auth) do
      {:ok, event} ->
        handle_event(event)
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("LiveKit webhook отклонён: #{inspect(reason)}")
        send_resp(conn, 401, "unauthorized")
    end
  end

  # E1: проверка подписи + аудит. E2 повесит сюда обработку attendance_records.
  defp handle_event(%{event: type} = event) do
    room_name = get_in(event, [:room, :name])

    Audit.log("livekit.#{type}",
      org_id: room_name && org_for_room(room_name),
      resource_type: :meeting,
      resource_id: room_name,
      metadata: %{participant: get_in(event, [:participant, :identity])}
    )

    :ok
  end

  defp handle_event(_), do: :ok

  defp org_for_room(room_name) do
    case Meetings.get_meeting_by_room(room_name) do
      %{org_id: org_id} -> org_id
      _ -> nil
    end
  end
end
