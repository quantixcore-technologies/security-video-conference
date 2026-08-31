defmodule Svc.RecordingsEgressTest do
  @moduledoc "Egress-оркестрация записи: auto_start (system), привязка egress_id, финализация, stop."
  use Svc.DataCase, async: true

  alias Svc.{Meetings, Recordings, Orgs, Accounts}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-egr"})

    {:ok, manager} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "mgr",
        full_name: "Manager",
        password: "SecurePass123!",
        role: :manager
      })

    %{org: org, manager: manager}
  end

  defp meeting(manager, policy) do
    {:ok, m} = Meetings.create_meeting(manager, %{title: "Совещание", recording_policy: policy})
    m
  end

  describe "auto_start/1" do
    test "policy :required → создаёт system-запись (requested_by nil, encrypted)", %{manager: m} do
      assert {:ok, rec} = Recordings.auto_start(meeting(m, :required))
      assert rec.status == :starting
      assert rec.requested_by == nil
      assert rec.encrypted == true
    end

    test "policy :optional → создаёт запись", %{manager: m} do
      assert {:ok, _rec} = Recordings.auto_start(meeting(m, :optional))
    end

    test "policy :off → {:error, :recording_disabled}", %{manager: m} do
      assert {:error, :recording_disabled} = Recordings.auto_start(meeting(m, :off))
    end
  end

  describe "egress lifecycle" do
    setup %{manager: m} do
      meeting = meeting(m, :required)
      {:ok, rec} = Recordings.auto_start(meeting)
      %{meeting: meeting, rec: rec}
    end

    test "pending_for_meeting возвращает :starting запись", %{meeting: meeting, rec: rec} do
      assert %{id: id} = Recordings.pending_for_meeting(meeting.id)
      assert id == rec.id
    end

    test "mark_active → egress_id + :active; get_by_egress_id находит", %{rec: rec} do
      {:ok, active} = Recordings.mark_active(rec, "EG_123")
      assert active.status == :active
      assert active.egress_id == "EG_123"
      assert Recordings.get_by_egress_id("EG_123").id == rec.id
    end

    test "mark_completed → :completed, pending пусто", %{meeting: meeting, rec: rec} do
      {:ok, active} = Recordings.mark_active(rec, "EG_777")
      {:ok, done} = Recordings.mark_completed(active, "recordings/x.mp4")
      assert done.status == :completed
      assert done.storage_path == "recordings/x.mp4"
      assert Recordings.pending_for_meeting(meeting.id) == nil
    end

    test "stop_for_meeting без egress_id → :ok (нечего останавливать)", %{meeting: meeting} do
      assert Recordings.stop_for_meeting(meeting) == :ok
    end
  end
end
