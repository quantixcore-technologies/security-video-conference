defmodule SvcWeb.API.MeetingController do
  @moduledoc "JSON API для Tauri-клиента (E1): получить токен входа в встречу."
  use SvcWeb, :controller

  alias Svc.{Meetings, LiveKit, Audit}

  def join(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case fetch_meeting(user.org_id, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})

      meeting ->
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
  end

  defp fetch_meeting(org_id, id) do
    Meetings.get_meeting!(org_id, id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
