defmodule SvcWeb.API.CaptureController do
  @moduledoc "API: приём детектов захвата от нативного клиента (Tauri/mobile) — E5."
  use SvcWeb, :controller

  alias Svc.{AntiCapture, Meetings}

  def create(conn, params) do
    user = conn.assigns.current_user

    case authorize_meeting(user, params["meeting_id"]) do
      {:ok, meeting_id} ->
        attrs = %{
          org_id: user.org_id,
          user_id: user.id,
          meeting_id: meeting_id,
          kind: params["kind"],
          platform: params["platform"],
          severity: params["severity"] || "info",
          detail: params["detail"] || %{},
          client_session_id: params["client_session_id"]
        }

        case AntiCapture.log_event(attrs) do
          {:ok, event} ->
            # E5-C: применяем пер-встречную политику (warn/eject) и возвращаем реакцию клиенту
            reaction = AntiCapture.enforce_policy(event)

            conn
            |> put_status(:created)
            |> json(%{id: event.id, status: "logged", reaction: reaction})

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
            conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
        end

      :error ->
        # meeting_id указан, но встреча не видна пользователю (чужая орг / не приглашён).
        # Не даём привязать детект захвата к чужой встрече и запускать её политику
        # (warn/eject) — та же граница видимости, что и для join (D-021). 404, чтобы
        # не раскрывать существование встречи.
        conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})
    end
  end

  # Без meeting_id — общий детект (напр. скриншот вне звонка), пишется без привязки.
  defp authorize_meeting(_user, nil), do: {:ok, nil}
  defp authorize_meeting(_user, ""), do: {:ok, nil}

  # С meeting_id — встреча ДОЛЖНА быть той же орг и видимой (организатор/приглашённый).
  defp authorize_meeting(user, meeting_id) do
    meeting = Meetings.get_meeting!(user.org_id, meeting_id)
    if Meetings.can_view_meeting?(user, meeting), do: {:ok, meeting.id}, else: :error
  rescue
    Ecto.NoResultsError -> :error
    Ecto.Query.CastError -> :error
  end
end
