defmodule Svc.Meetings.ICal do
  @moduledoc """
  Генерация iCalendar (.ics) для встреч (E3, RFC 5545 базовый VEVENT).
  Для импорта во внешние календари (Outlook/Google). Время — UTC.
  """
  alias Svc.Meetings.Meeting

  @doc "Строит .ics-документ для одной встречи (CRLF-окончания по RFC 5545)."
  def to_ics(%Meeting{} = m) do
    ([
       "BEGIN:VCALENDAR",
       "VERSION:2.0",
       "PRODID:-//SVC//Security Video Conference//RU",
       "CALSCALE:GREGORIAN",
       "METHOD:PUBLISH",
       "BEGIN:VEVENT",
       "UID:meeting-#{m.id}@svc",
       "DTSTAMP:#{stamp(DateTime.utc_now())}",
       "DTSTART:#{stamp(m.scheduled_start)}"
     ] ++
       end_line(m) ++
       [
         "SUMMARY:#{escape(m.title)}",
         "STATUS:#{ical_status(m.status)}",
         "END:VEVENT",
         "END:VCALENDAR"
       ])
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  @doc "Имя файла для скачивания."
  def filename(%Meeting{} = m), do: "meeting-#{m.id}.ics"

  defp end_line(%Meeting{scheduled_end: nil}), do: []
  defp end_line(%Meeting{scheduled_end: e}), do: ["DTEND:#{stamp(e)}"]

  defp stamp(nil), do: ""

  defp stamp(%DateTime{} = dt),
    do: dt |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end

  defp ical_status(:ended), do: "CANCELLED"
  defp ical_status(_), do: "CONFIRMED"
end
