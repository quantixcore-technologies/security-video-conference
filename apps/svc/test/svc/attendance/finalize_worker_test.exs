defmodule Svc.Attendance.FinalizeWorkerTest do
  use Svc.DataCase, async: true
  use Oban.Testing, repo: Svc.Repo

  alias Svc.{Attendance, Meetings, Accounts, Orgs}
  alias Svc.Attendance.FinalizeWorker

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, mgr} = mk(org, "mgr", :manager)
    {:ok, alice} = mk(org, "alice", :employee)
    {:ok, meeting} = Meetings.create_meeting(mgr, %{title: "Совещание"})
    %{org: org, meeting: meeting, alice: alice}
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

  test "perform помечает absent приглашённых, не вошедших (D-008)", %{
    org: org,
    meeting: meeting,
    alice: alice
  } do
    Attendance.add_invitee(meeting, alice)

    assert :ok =
             perform_job(FinalizeWorker, %{"meeting_id" => meeting.id, "org_id" => org.id})

    assert [record] = Attendance.list_attendance(meeting.id)
    assert record.user_id == alice.id
    assert record.status == :absent
  end

  test "perform для удалённой встречи не падает", %{org: org} do
    assert :ok = perform_job(FinalizeWorker, %{"meeting_id" => 999_999, "org_id" => org.id})
  end
end
