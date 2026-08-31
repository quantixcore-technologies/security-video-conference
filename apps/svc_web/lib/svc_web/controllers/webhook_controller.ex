defmodule SvcWeb.WebhookController do
  @moduledoc "Приём LiveKit-вебхуков (E1/E2). Проверка подписи → attendance + аудит."
  use SvcWeb, :controller
  require Logger

  alias Svc.{LiveKit, Audit, Meetings, Attendance, Recordings}
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
    with %Meeting{} = meeting <- meeting_from(event) do
      Meetings.start_meeting(meeting)

      # E: авто-запись по политике встречи (D-009) + запуск LiveKit Egress (best-effort)
      if Recordings.recording_enabled?(meeting), do: Recordings.auto_start(meeting)
    end

    audit(type, event)
  end

  defp handle_event(%{event: "room_finished" = type} = event) do
    with %Meeting{} = meeting <- meeting_from(event) do
      Meetings.end_meeting(meeting)

      # E: останавливаем egress активной записи (финализация — из вебхука egress_ended)
      Recordings.stop_for_meeting(meeting)

      %{meeting_id: meeting.id, org_id: meeting.org_id}
      |> Svc.Attendance.FinalizeWorker.new()
      |> Oban.insert()
    end

    audit(type, event)
  end

  # E: egress запущен → привязываем egress_id к :starting-записи встречи
  defp handle_event(%{event: "egress_started" = type, egress_info: %{} = ei} = event) do
    with %Meeting{} = meeting <- Meetings.get_meeting_by_room(ei[:room_name] || ""),
         rec when not is_nil(rec) <- Recordings.pending_for_meeting(meeting.id),
         eid when is_binary(eid) <- ei[:egress_id] do
      Recordings.mark_active(rec, eid)
    end

    audit(type, event)
  end

  # E: egress завершён → финализируем запись (status: :completed)
  defp handle_event(%{event: "egress_ended" = type, egress_info: %{} = ei} = event) do
    with eid when is_binary(eid) <- ei[:egress_id],
         rec when not is_nil(rec) <- Recordings.get_by_egress_id(eid) do
      Recordings.mark_completed(rec, ei[:room_name])
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
