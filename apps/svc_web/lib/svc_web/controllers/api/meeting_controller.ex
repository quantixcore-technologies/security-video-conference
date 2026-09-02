defmodule SvcWeb.API.MeetingController do
  @moduledoc "JSON API для Tauri-клиента (E1): получить токен входа в встречу."
  use SvcWeb, :controller

  alias Svc.{Meetings, LiveKit, Audit, Geo}

  def index(conn, _params) do
    user = conn.assigns.current_user

    meetings =
      for m <- Meetings.list_visible_meetings(user) do
        %{
          id: m.id,
          title: m.title,
          status: m.status,
          type: m.type,
          scheduled_start: m.scheduled_start,
          scheduled_end: m.scheduled_end
        }
      end

    json(conn, %{meetings: meetings})
  end

  def join(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    case fetch_meeting(user.org_id, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})

      meeting ->
        # E7 pre-join gate: классификация IP + запись GPS (нативный клиент).
        # MVP без MMDB: gate возвращает только :allow/:flag (никогда :block — см. Svc.Geo).
        # flag = пометка для ручной проверки, НЕ отказ → в звонок пускаем. Когда подключим
        # MaxMind MMDB (locus) и появится :block — компилятор потребует ветку отказа (D-012).
        case Geo.gate(user.org_id, remote_ip(conn), gate_opts(user, meeting, params)) do
          {:allow, _reason} -> issue_token(conn, user, meeting)
          {:flag, _reason} -> issue_token(conn, user, meeting)
        end
    end
  end

  defp issue_token(conn, user, meeting) do
    case LiveKit.join_token(user, meeting) do
      {:ok, token} ->
        Audit.log_action(user, :meeting_join,
          resource_type: :meeting,
          resource_id: meeting.id
        )

        json(conn, %{
          url: LiveKit.url(),
          token: token,
          room: meeting.livekit_room_name
        })

      {:error, reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: to_string(reason)})
    end
  end

  defp gate_opts(user, meeting, params) do
    [
      user_id: user.id,
      meeting_id: meeting.id,
      gps_lat: to_float(params["lat"]),
      gps_lon: to_float(params["lon"]),
      gps_accuracy: to_float(params["accuracy"])
    ]
  end

  defp to_float(nil), do: nil
  defp to_float(n) when is_number(n), do: n / 1

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp fetch_meeting(org_id, id) do
    Meetings.get_meeting!(org_id, id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
