defmodule SvcWeb.MeetingController do
  use SvcWeb, :controller

  alias Svc.Meetings
  alias Svc.Meetings.ICal

  @doc "Скачивание встречи в формате iCalendar (.ics) — E3."
  def ics(conn, %{"id" => id}) do
    actor = conn.assigns.current_user
    meeting = Meetings.get_meeting!(actor.org_id, id)

    conn
    |> put_resp_content_type("text/calendar")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{ICal.filename(meeting)}"))
    |> send_resp(200, ICal.to_ics(meeting))
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Встреча не найдена.")
      |> redirect(to: ~p"/admin/meetings")
  end
end
