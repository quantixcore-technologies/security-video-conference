defmodule SvcWeb.API.CaptureController do
  @moduledoc "API: приём детектов захвата от нативного клиента (Tauri/mobile) — E5."
  use SvcWeb, :controller

  alias Svc.AntiCapture

  def create(conn, params) do
    user = conn.assigns.current_user

    attrs = %{
      org_id: user.org_id,
      user_id: user.id,
      meeting_id: params["meeting_id"],
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
  end
end
