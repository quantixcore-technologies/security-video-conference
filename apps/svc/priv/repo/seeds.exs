# Демо-данные для визуальной проверки админки (E0/E1/E2).
# Запуск: DB_PORT=5434 mix run apps/svc/priv/repo/seeds.exs
# Идемпотентно: пропускает, если организация уже есть.

alias Svc.{Orgs, Accounts, Meetings, Attendance}

if Orgs.default_organization() do
  IO.puts("Seed пропущен — организация уже существует.")
else
  {:ok, org} = Orgs.create_organization(%{name: "Министерство цифрового развития", slug: "mincifra"})
  {:ok, upr} = Orgs.create_department(%{org_id: org.id, name: "Управление ИТ-инфраструктуры"})

  {:ok, otd} =
    Orgs.create_department(%{org_id: org.id, parent_id: upr.id, name: "Отдел сетевой безопасности"})

  mk = fn username, full_name, role, dept ->
    {:ok, u} =
      Accounts.create_user(%{
        org_id: org.id,
        department_id: dept,
        username: username,
        full_name: full_name,
        phone: "+99890#{:rand.uniform(9_999_999)}",
        password: "AdminPass12345",
        role: role
      })

    u
  end

  admin = mk.("admin", "Каримов Алишер Рустамович", :super_admin, upr.id)
  _hr = mk.("hradmin", "Юсупова Дилноза Фарходовна", :admin_hr, upr.id)
  _mgr = mk.("manager", "Тошматов Бахтиёр Шавкатович", :manager, otd.id)
  emp1 = mk.("ivanov", "Иванов Сергей Петрович", :employee, otd.id)
  emp2 = mk.("petrov", "Петров Андрей Николаевич", :employee, otd.id)
  emp3 = mk.("sidorov", "Сидоров Дмитрий Олегович", :employee, otd.id)

  start = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)
  finish = DateTime.add(start, 3600, :second)

  {:ok, meeting} =
    Meetings.create_meeting(admin, %{
      title: "Еженедельная планёрка по кибербезопасности",
      type: :scheduled,
      scheduled_start: start,
      scheduled_end: finish,
      recording_policy: :optional,
      late_threshold_seconds: 300
    })

  for e <- [emp1, emp2, emp3], do: Attendance.add_invitee(meeting, e)

  # emp1 — вовремя (present), emp2 — опоздал (late), emp3 — не пришёл (absent)
  Attendance.record_join(meeting, emp1.id, start)
  Attendance.record_join(meeting, emp2.id, DateTime.add(start, 600, :second))
  Attendance.record_leave(meeting, emp1.id, DateTime.add(start, 1800, :second))
  Attendance.finalize_absent(meeting)

  IO.puts("""
  Seed создан:
    Организация: #{org.name}
    Вход: admin / AdminPass12345  (super_admin, 2FA выключена)
    Встреча: #{meeting.title} (3 в ростере: present/late/absent)
  """)
end
