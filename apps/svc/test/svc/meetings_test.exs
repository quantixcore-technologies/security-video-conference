defmodule Svc.MeetingsTest do
  use Svc.DataCase, async: true

  alias Svc.{Meetings, Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved"})
    {:ok, manager} = mk(org, "mgr", :manager)
    {:ok, employee} = mk(org, "emp", :employee)
    %{org: org, manager: manager, employee: employee}
  end

  defp mk(org, username, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: role
    })
  end

  describe "create_meeting/2" do
    test "manager создаёт встречу, генерится room_name", %{manager: m} do
      assert {:ok, meeting} = Meetings.create_meeting(m, %{title: "Планёрка"})
      assert meeting.title == "Планёрка"
      assert meeting.organizer_id == m.id
      assert meeting.org_id == m.org_id
      assert meeting.status == :planned
      assert meeting.recording_policy == :off
      assert String.starts_with?(meeting.livekit_room_name, "room_")
    end

    test "room_name уникален между встречами", %{manager: m} do
      {:ok, a} = Meetings.create_meeting(m, %{title: "Встреча А"})
      {:ok, b} = Meetings.create_meeting(m, %{title: "Встреча Б"})
      refute a.livekit_room_name == b.livekit_room_name
    end

    test "employee НЕ может создавать встречи (RBAC, D-007)", %{employee: e} do
      assert {:error, :unauthorized} = Meetings.create_meeting(e, %{title: "Нельзя"})
    end

    test "требует title", %{manager: m} do
      assert {:error, cs} = Meetings.create_meeting(m, %{title: ""})
      assert errors_on(cs)[:title]
    end

    test "scheduled_end должно быть позже start", %{manager: m} do
      start = ~U[2026-06-10 10:00:00.000000Z]
      finish = ~U[2026-06-10 09:00:00.000000Z]

      assert {:error, cs} =
               Meetings.create_meeting(m, %{title: "Бяка", scheduled_start: start, scheduled_end: finish})

      assert errors_on(cs)[:scheduled_end]
    end

    test "recording_policy можно задать (D-009)", %{manager: m} do
      assert {:ok, meeting} =
               Meetings.create_meeting(m, %{title: "С записью", recording_policy: :required})

      assert meeting.recording_policy == :required
    end
  end

  describe "жизненный цикл и доступ" do
    setup %{manager: m} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Встреча"})
      %{meeting: meeting}
    end

    test "start_meeting / end_meeting меняют статус", %{meeting: meeting} do
      assert {:ok, m1} = Meetings.start_meeting(meeting)
      assert m1.status == :live
      assert {:ok, m2} = Meetings.end_meeting(m1)
      assert m2.status == :ended
    end

    test "update_meeting меняет название и политику записи", %{meeting: meeting} do
      assert {:ok, m} =
               Meetings.update_meeting(meeting, %{
                 "title" => "Новое название",
                 "recording_policy" => "required"
               })

      assert m.title == "Новое название"
      assert m.recording_policy == :required
    end

    test "update_meeting не трогает room_name и org", %{meeting: meeting} do
      room = meeting.livekit_room_name

      {:ok, m} =
        Meetings.update_meeting(meeting, %{
          "title" => "Другое",
          "livekit_room_name" => "hacked",
          "org_id" => 999_999
        })

      assert m.livekit_room_name == room
      assert m.org_id == meeting.org_id
    end

    test "update_meeting валидирует расписание (конец позже начала)", %{meeting: meeting} do
      assert {:error, cs} =
               Meetings.update_meeting(meeting, %{
                 "scheduled_start" => ~U[2026-06-10 10:00:00Z],
                 "scheduled_end" => ~U[2026-06-10 09:00:00Z]
               })

      assert errors_on(cs)[:scheduled_end]
    end

    test "get_meeting_by_room находит встречу", %{meeting: meeting} do
      found = Meetings.get_meeting_by_room(meeting.livekit_room_name)
      assert found.id == meeting.id
    end

    test "list_meetings scoped по org (D-005)", %{org: org, meeting: meeting} do
      {:ok, other} = Orgs.create_organization(%{name: "Чужое", slug: "chuzhoe"})
      {:ok, other_mgr} = mk(other, "omgr", :manager)
      {:ok, _foreign} = Meetings.create_meeting(other_mgr, %{title: "Чужая встреча"})

      ids = Meetings.list_meetings(org.id) |> Enum.map(& &1.id)
      assert meeting.id in ids
      assert length(ids) == 1
    end
  end
end
