defmodule Svc.AntiCapturePolicyTest do
  @moduledoc "E5-C: пер-встречная анти-захват политика (watermark on/off, реакция warn/eject)."
  use Svc.DataCase, async: true

  alias Svc.{Meetings, AntiCapture, Notifications, Audit, Orgs, Accounts}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-e5c"})
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

  defp log_capture(org, user, meeting) do
    {:ok, event} =
      AntiCapture.log_event(%{
        org_id: org.id,
        user_id: user.id,
        meeting_id: meeting.id,
        kind: "recorder_detected",
        platform: "windows"
      })

    event
  end

  describe "per-meeting policy fields" do
    test "defaults: watermark on, reaction none", %{manager: m} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Default policy"})
      assert meeting.watermark_enabled == true
      assert meeting.capture_reaction == :none
    end

    test "watermark off + reaction eject сохраняются", %{manager: m} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Strict", capture_reaction: :eject})
      {:ok, meeting} = Meetings.update_meeting(meeting, %{"watermark_enabled" => false})
      assert meeting.watermark_enabled == false
      assert meeting.capture_reaction == :eject
    end

    test "неизвестная реакция отклоняется changeset'ом", %{manager: m} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Bad"})
      assert {:error, cs} = Meetings.update_meeting(meeting, %{"capture_reaction" => "nuke"})
      assert errors_on(cs)[:capture_reaction]
    end
  end

  describe "enforce_policy/1" do
    test "reaction :none → :none, без уведомления", %{org: org, manager: m, employee: e} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "None"})
      before = Notifications.unread_count(m.id)

      assert AntiCapture.enforce_policy(log_capture(org, e, meeting)) == :none
      assert Notifications.unread_count(m.id) == before
    end

    test "reaction :warn → :warn + уведомление организатору + audit",
         %{org: org, manager: m, employee: e} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Warn", capture_reaction: :warn})
      before = Notifications.unread_count(m.id)

      assert AntiCapture.enforce_policy(log_capture(org, e, meeting)) == :warn
      assert Notifications.unread_count(m.id) == before + 1
      assert Enum.any?(Audit.list_logs(org.id), &(&1.action == "capture_reaction"))
    end

    test "reaction :eject → :eject + audit (LiveKit best-effort)",
         %{org: org, manager: m, employee: e} do
      {:ok, meeting} = Meetings.create_meeting(m, %{title: "Eject", capture_reaction: :eject})

      assert AntiCapture.enforce_policy(log_capture(org, e, meeting)) == :eject
      assert Enum.any?(Audit.list_logs(org.id), &(&1.action == "capture_reaction"))
    end

    test "событие без встречи → :none", %{org: org, employee: e} do
      {:ok, event} =
        AntiCapture.log_event(%{org_id: org.id, user_id: e.id, kind: "recorder_detected"})

      assert AntiCapture.enforce_policy(event) == :none
    end
  end
end
