defmodule Svc.Meetings.ICalTest do
  use ExUnit.Case, async: true

  alias Svc.Meetings.{ICal, Meeting}

  test "to_ics содержит обязательные VCALENDAR/VEVENT поля" do
    m = %Meeting{
      id: 42,
      title: "Планёрка",
      status: :planned,
      scheduled_start: ~U[2026-06-10 10:00:00Z],
      scheduled_end: ~U[2026-06-10 11:00:00Z]
    }

    ics = ICal.to_ics(m)

    assert ics =~ "BEGIN:VCALENDAR"
    assert ics =~ "VERSION:2.0"
    assert ics =~ "BEGIN:VEVENT"
    assert ics =~ "UID:meeting-42@svc"
    assert ics =~ "SUMMARY:Планёрка"
    assert ics =~ "DTSTART:20260610T100000Z"
    assert ics =~ "DTEND:20260610T110000Z"
    assert ics =~ "STATUS:CONFIRMED"
    assert ics =~ "END:VCALENDAR"
    assert String.contains?(ics, "\r\n")
  end

  test "завершённая встреча → STATUS:CANCELLED" do
    m = %Meeting{id: 1, title: "X", status: :ended, scheduled_start: ~U[2026-06-10 10:00:00Z]}
    assert ICal.to_ics(m) =~ "STATUS:CANCELLED"
  end

  test "без scheduled_end — нет DTEND" do
    m = %Meeting{id: 1, title: "X", status: :planned, scheduled_start: ~U[2026-06-10 10:00:00Z]}
    refute ICal.to_ics(m) =~ "DTEND:"
  end

  test "экранирует спецсимволы в SUMMARY" do
    m = %Meeting{
      id: 1,
      title: "Встреча; отдел, А",
      status: :planned,
      scheduled_start: ~U[2026-06-10 10:00:00Z]
    }

    assert ICal.to_ics(m) =~ "SUMMARY:Встреча\\; отдел\\, А"
  end

  test "filename по id" do
    assert ICal.filename(%Meeting{id: 7}) == "meeting-7.ics"
  end
end
