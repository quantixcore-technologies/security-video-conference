defmodule Svc.AntiCaptureTest do
  use Svc.DataCase, async: true

  alias Svc.{AntiCapture, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    %{org: org}
  end

  test "log_event создаёт событие захвата", %{org: org} do
    assert {:ok, e} =
             AntiCapture.log_event(%{
               org_id: org.id,
               kind: :screenshot_detected,
               platform: "windows",
               severity: :warning
             })

    assert e.kind == :screenshot_detected
    assert e.severity == :warning
    assert e.occurred_at
  end

  test "log_event подставляет occurred_at и severity по умолчанию", %{org: org} do
    {:ok, e} = AntiCapture.log_event(%{org_id: org.id, kind: :recorder_detected})
    assert e.occurred_at
    assert e.severity == :info
  end

  test "list_events возвращает события организации", %{org: org} do
    AntiCapture.log_event(%{org_id: org.id, kind: :screenshot_detected})
    AntiCapture.log_event(%{org_id: org.id, kind: :recorder_detected})
    assert length(AntiCapture.list_events(org.id)) == 2
  end

  test "list_events изолирован по org (D-005)", %{org: org} do
    {:ok, other} = Orgs.create_organization(%{name: "Чужое", slug: "ch"})
    AntiCapture.log_event(%{org_id: other.id, kind: :screenshot_detected})
    assert AntiCapture.list_events(org.id) == []
  end

  test "critical_count считает только критические", %{org: org} do
    AntiCapture.log_event(%{org_id: org.id, kind: :recorder_detected, severity: :critical})
    AntiCapture.log_event(%{org_id: org.id, kind: :screenshot_detected, severity: :info})
    assert AntiCapture.critical_count(org.id) == 1
  end
end
