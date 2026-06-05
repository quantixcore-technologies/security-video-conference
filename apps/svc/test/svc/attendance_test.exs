defmodule Svc.AttendanceTest do
  use Svc.DataCase, async: true

  alias Svc.{Attendance, Meetings, Accounts, Orgs}

  @start ~U[2026-06-10 10:00:00.000000Z]
  @finish ~U[2026-06-10 11:00:00.000000Z]

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org"})
    {:ok, mgr} = mk(org, "mgr", :manager)
    {:ok, alice} = mk(org, "alice", :employee)
    {:ok, bob} = mk(org, "bob", :employee)

    {:ok, meeting} =
      Meetings.create_meeting(mgr, %{
        title: "Совещание",
        scheduled_start: @start,
        scheduled_end: @finish,
        late_threshold_seconds: 300
      })

    %{org: org, meeting: meeting, alice: alice, bob: bob}
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

  describe "ростер" do
    test "add_invitee добавляет, повтор идемпотентен", %{meeting: m, alice: a} do
      assert {:ok, _} = Attendance.add_invitee(m, a)
      assert {:ok, _} = Attendance.add_invitee(m, a, false)
      assert length(Attendance.list_invitees(m.id)) == 1
    end
  end

  describe "RSVP (E3)" do
    setup %{meeting: m, alice: a} do
      {:ok, _} = Attendance.add_invitee(m, a)
      :ok
    end

    test "приглашённый по умолчанию pending", %{meeting: m, alice: a} do
      assert Attendance.get_invitee(m.id, a.id).rsvp_status == :pending
    end

    test "set_rsvp фиксирует ответ и время", %{meeting: m, alice: a} do
      assert {:ok, inv} = Attendance.set_rsvp(m.id, a.id, :accepted)
      assert inv.rsvp_status == :accepted
      assert inv.rsvp_at
    end

    test "set_rsvp можно изменить ответ", %{meeting: m, alice: a} do
      {:ok, _} = Attendance.set_rsvp(m.id, a.id, :accepted)
      assert {:ok, inv} = Attendance.set_rsvp(m.id, a.id, :declined)
      assert inv.rsvp_status == :declined
    end

    test "set_rsvp для не-приглашённого → not_invited", %{meeting: m, bob: b} do
      assert {:error, :not_invited} = Attendance.set_rsvp(m.id, b.id, :accepted)
    end

    test "list_invitees_with_users preload-ит пользователя", %{meeting: m} do
      assert [inv] = Attendance.list_invitees_with_users(m.id)
      assert inv.user.full_name == "User alice"
    end
  end

  describe "record_join — статус по времени" do
    test "вовремя → present", %{meeting: m, alice: a} do
      {:ok, rec} = Attendance.record_join(m, a.id, @start)
      assert rec.status == :present
    end

    test "в пределах порога (5 мин) → present", %{meeting: m, alice: a} do
      {:ok, rec} = Attendance.record_join(m, a.id, ~U[2026-06-10 10:04:00.000000Z])
      assert rec.status == :present
    end

    test "после порога → late", %{meeting: m, alice: a} do
      {:ok, rec} = Attendance.record_join(m, a.id, ~U[2026-06-10 10:10:00.000000Z])
      assert rec.status == :late
    end

    test "ad-hoc (без расписания) → present", %{alice: a} do
      {:ok, org} = Orgs.create_organization(%{name: "Орг Икс", slug: "x"})
      {:ok, mgr} = mk(org, "mgr2", :manager)
      {:ok, adhoc} = Meetings.create_meeting(mgr, %{title: "Спонтанная", type: :ad_hoc})
      {:ok, rec} = Attendance.record_join(adhoc, a.id, ~U[2026-06-10 15:00:00.000000Z])
      assert rec.status == :present
    end

    test "идемпотентно — повторный join обновляет, не дублирует", %{meeting: m, alice: a} do
      {:ok, _} = Attendance.record_join(m, a.id, @start)
      {:ok, _} = Attendance.record_join(m, a.id, @start)
      assert length(Attendance.list_attendance(m.id)) == 1
    end
  end

  describe "record_leave" do
    test "считает total_seconds и left_at", %{meeting: m, alice: a} do
      {:ok, _} = Attendance.record_join(m, a.id, @start)
      {:ok, rec} = Attendance.record_leave(m, a.id, ~U[2026-06-10 10:30:00.000000Z])
      assert rec.left_at == ~U[2026-06-10 10:30:00.000000Z]
      assert rec.total_seconds == 1800
    end

    test "уход до конца → left_early", %{meeting: m, alice: a} do
      {:ok, _} = Attendance.record_join(m, a.id, @start)
      {:ok, rec} = Attendance.record_leave(m, a.id, ~U[2026-06-10 10:30:00.000000Z])
      assert rec.status == :left_early
    end

    test "без записи входа → ошибка", %{meeting: m, bob: b} do
      assert {:error, :no_join_record} = Attendance.record_leave(m, b.id, @finish)
    end
  end

  describe "finalize_absent (D-008)" do
    test "приглашённый, не вошедший → absent", %{meeting: m, alice: a, bob: b} do
      Attendance.add_invitee(m, a)
      Attendance.add_invitee(m, b)
      {:ok, _} = Attendance.record_join(m, a.id, @start)

      :ok = Attendance.finalize_absent(m)

      records = Attendance.list_attendance(m.id)
      by_user = Map.new(records, &{&1.user_id, &1.status})
      assert by_user[a.id] == :present
      assert by_user[b.id] == :absent
    end

    test "идемпотентно — не перезаписывает существующие", %{meeting: m, alice: a} do
      Attendance.add_invitee(m, a)
      {:ok, _} = Attendance.record_join(m, a.id, @start)
      :ok = Attendance.finalize_absent(m)
      :ok = Attendance.finalize_absent(m)
      assert length(Attendance.list_attendance(m.id)) == 1
    end
  end
end
