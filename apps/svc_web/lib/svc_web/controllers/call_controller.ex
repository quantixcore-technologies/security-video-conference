defmodule SvcWeb.CallController do
  @moduledoc """
  DEV-страница живого видеозвонка из браузера (тест инфры LiveKit, E1).
  В проде видео идёт через Tauri-клиент (D-001/D-002); это — для отладки.
  """
  use SvcWeb, :controller

  alias Svc.{Meetings, LiveKit, Audit, Geo}

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    meeting = Meetings.get_meeting!(user.org_id, id)

    # E7: pre-join сетевая/гео-проверка (flag-режим — логируем, не блокируем без MMDB)
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    Geo.gate(user.org_id, ip, meeting_id: meeting.id, user_id: user.id)

    case LiveKit.join_token(user, meeting) do
      {:ok, token} ->
        Audit.log_action(user, :meeting_join, resource_type: :meeting, resource_id: meeting.id)

        render(conn, :show,
          meeting: meeting,
          token: token,
          livekit_url: LiveKit.url(),
          current_user: user,
          layout: false
        )

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text("LiveKit недоступен: #{inspect(reason)}")
    end
  rescue
    Ecto.NoResultsError ->
      conn |> put_status(:not_found) |> text("Встреча не найдена")
  end
end
