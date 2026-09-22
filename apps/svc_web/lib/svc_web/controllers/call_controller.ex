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

    # S45: то же правило, что и в мобильном API — второй выход закрывает вход.
    case Meetings.join_guard(user, meeting) do
      {:blocked, _} ->
        # Именно 302, без `put_status(:forbidden)`: браузер НЕ идёт по Location
        # при 4xx — человек видел бы пустую страницу «You are being redirected»
        # вместо своей встречи с объяснением. Отказ фиксируется в аудите и
        # журнале безопасности, а JSON-API по-прежнему отвечает 403.
        conn
        |> put_flash(
          :error,
          gettext("Вы вышли из звонка второй раз — повторный вход закрыт.")
        )
        |> redirect(to: ~p"/admin/meetings/#{meeting.id}")

      guard ->
        render_call(conn, user, meeting, guard)
    end
  rescue
    Ecto.NoResultsError ->
      conn |> put_status(:not_found) |> text(gettext("Встреча не найдена"))
  end

  defp render_call(conn, user, meeting, guard) do
    case LiveKit.join_token(user, meeting) do
      {:ok, token} ->
        Audit.log_action(user, :meeting_join, resource_type: :meeting, resource_id: meeting.id)

        conn
        |> maybe_warn(guard)
        |> render(:show,
          meeting: meeting,
          token: token,
          livekit_url: LiveKit.url(),
          current_user: user,
          layout: false
        )

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text(gettext("LiveKit недоступен: %{reason}", reason: inspect(reason)))
    end
  end

  # Первый выход — предупреждение и ещё одна попытка (S45).
  defp maybe_warn(conn, {:warn, :last_attempt}) do
    put_flash(
      conn,
      :error,
      gettext("Это последний вход в звонок: выйдете ещё раз — вернуться уже не сможете.")
    )
  end

  defp maybe_warn(conn, _), do: conn
end
