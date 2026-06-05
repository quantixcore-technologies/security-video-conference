defmodule SvcWeb.WebhookController do
  @moduledoc "Приём LiveKit-вебхуков (E1/E2). Проверка подписи → attendance + аудит."
  use SvcWeb, :controller
  require Logger

  alias Svc.{LiveKit, Audit, Meetings, Attendance}
  alias Svc.Meetings.Meeting

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

  # E2: события LiveKit → обновление посещаемости + аудит.
  defp handle_event(%{event: "participant_joined" = type} = event) do
    with %Meeting{} = meeting <- meeting_from(event),
         user_id when is_integer(user_id) <- user_id_from(event) do
      Attendance.record_join(meeting, user_id, event_time(event))
    end

    audit(type, event)
  end

  defp handle_event(%{event: "participant_left" = type} = event) do
    with %Meeting{} = meeting <- meeting_from(event),
         user_id when is_integer(user_id) <- user_id_from(event) do
      Attendance.record_leave(meeting, user_id, event_time(event))
    end

    audit(type, event)
  end

  defp handle_event(%{event: "room_started" = type} = event) do
    with %Meeting{} = meeting <- meeting_from(event), do: Meetings.start_meeting(meeting)
    audit(type, event)
  end

  defp handle_event(%{event: "room_finished" = type} = event) do
    with %Meeting{} = meeting <- meeting_from(event) do
      Meetings.end_meeting(meeting)
      Attendance.finalize_absent(meeting)
    end

    audit(type, event)
  end

  defp handle_event(%{event: type} = event), do: audit(type, event)
  defp handle_event(_), do: :ok

  defp audit(type, event) do
    room_name = get_in(event, [:room, :name])

    Audit.log("livekit.#{type}",
      org_id: room_name && org_for_room(room_name),
      resource_type: :meeting,
      resource_id: room_name,
      metadata: %{participant: get_in(event, [:participant, :identity])}
    )

    :ok
  end

  defp meeting_from(event) do
    case get_in(event, [:room, :name]) do
      nil -> nil
      name -> Meetings.get_meeting_by_room(name)
    end
  end

  # identity LiveKit = "user-{id}" (см. Svc.LiveKit.identity/1)
  defp user_id_from(event) do
    case get_in(event, [:participant, :identity]) do
      "user-" <> id ->
        case Integer.parse(id) do
          {n, ""} -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp event_time(event) do
    with ts when is_integer(ts) <- event[:created_at],
         {:ok, dt} <- DateTime.from_unix(ts) do
      dt
    else
      _ -> DateTime.utc_now()
    end
  end

  defp org_for_room(room_name) do
    case Meetings.get_meeting_by_room(room_name) do
      %{org_id: org_id} -> org_id
      _ -> nil
    end
  end
end
