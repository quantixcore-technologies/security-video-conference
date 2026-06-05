defmodule Svc.RecordingsTest do
  use Svc.DataCase, async: true

  alias Svc.{Recordings, Meetings, Accounts, Orgs}
  alias Svc.Accounts.User

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, mgr} = mk(org, "mgr", :manager)
    %{org: org, mgr: mgr}
  end

  defp mk(org, u, r) do
    Accounts.create_user(%{
      org_id: org.id,
      username: u,
      full_name: "User #{u}",
      password: "SecurePass123!",
      role: r
    })
  end

  defp meeting(mgr, policy) do
    {:ok, m} = Meetings.create_meeting(mgr, %{title: "Встреча", recording_policy: policy})
    m
  end

  describe "start_recording/2 (D-009)" do
    test "создаёт запись, когда политика optional", %{mgr: mgr} do
      assert {:ok, rec} = Recordings.start_recording(meeting(mgr, :optional), mgr)
      assert rec.status == :starting
      assert rec.encrypted == true
      assert rec.requested_by == mgr.id
    end

    test "создаёт запись, когда политика required", %{mgr: mgr} do
      assert {:ok, _} = Recordings.start_recording(meeting(mgr, :required), mgr)
    end

    test "отказ, когда политика off", %{mgr: mgr} do
      assert {:error, :recording_disabled} =
               Recordings.start_recording(meeting(mgr, :off), mgr)
    end
  end

  describe "жизненный цикл egress" do
    setup %{mgr: mgr} do
      {:ok, rec} = Recordings.start_recording(meeting(mgr, :required), mgr)
      %{rec: rec}
    end

    test "mark_active фиксирует egress_id", %{rec: rec} do
      assert {:ok, r} = Recordings.mark_active(rec, "EG_abc123")
      assert r.egress_id == "EG_abc123"
      assert r.status == :active
    end

    test "mark_completed завершает с путём", %{rec: rec} do
      {:ok, rec} = Recordings.mark_active(rec, "EG_abc123")
      assert {:ok, r} = Recordings.mark_completed(rec, "s3://bucket/rec.mp4")
      assert r.status == :completed
      assert r.storage_path == "s3://bucket/rec.mp4"
      assert r.ended_at
    end

    test "list_recordings возвращает записи встречи", %{rec: rec} do
      assert [found] = Recordings.list_recordings(rec.meeting_id)
      assert found.id == rec.id
    end
  end

  describe "can_access?/2 (RBAC, D-007)" do
    test "org-wide роли той же org — доступ", %{org: org, mgr: mgr} do
      {:ok, rec} = Recordings.start_recording(meeting(mgr, :required), mgr)
      assert Recordings.can_access?(%User{org_id: org.id, role: :admin_hr}, rec)
      assert Recordings.can_access?(%User{org_id: org.id, role: :security_officer}, rec)
    end

    test "employee — нет доступа", %{org: org, mgr: mgr} do
      {:ok, rec} = Recordings.start_recording(meeting(mgr, :required), mgr)
      refute Recordings.can_access?(%User{org_id: org.id, role: :employee}, rec)
    end

    test "чужая организация — нет доступа (D-005)", %{mgr: mgr} do
      {:ok, rec} = Recordings.start_recording(meeting(mgr, :required), mgr)
      refute Recordings.can_access?(%User{org_id: rec.org_id + 999, role: :admin_hr}, rec)
    end
  end
end
