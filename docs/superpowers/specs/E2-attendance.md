# E2 — Посещаемость + Личность (детальный спек)

> **Статус:** Срез 1, Фаза 3 — детальный спек. **← конец Milestone 1.**
> **ТЗ:** Контроль сотрудников (кто был / кто отсутствовал), Журнал посещаемости, Фото/ФИО/Номер.
> **Зависит:** E1 (meetings, webhooks), E0 (users-профиль). Версии — Context7 (NET-SCAN-01).

## Цель
Журнал «кто присутствовал, а кто отсутствовал» (D-008, гибрид). Автоматический расчёт статусов из LiveKit-webhooks; ростер для запланированных встреч; профиль сотрудника (Фото/ФИО/Номер); опциональная серверная запись (D-009). Журнал — RBAC-scoped (manager видит свой отдел).

## Контексты
- **`Svc.Attendance`** (apps/svc): ростер, attendance_records, расчёт статусов, журнал-запросы.
- **`Svc.Recordings`** (apps/svc): опц. серверная запись через Egress.
- **`Svc.Accounts`** (E0): enrollment профиля (Фото/ФИО/Номер уже в users).

## Доменные сущности (Ecto, `org_id`)

### meeting_invitees (ростер)
`id` · `org_id` · `meeting_id →meetings` · `user_id →users` · `expected :boolean` (default true) · timestamps.
Индексы: `unique(meeting_id, user_id)`, `(user_id)`.

### attendance_records (журнал)
`id` · `org_id` · `meeting_id` · `user_id` · `status [:present,:late,:left_early,:absent]` · `joined_at (nullable)` · `left_at (nullable)` · `total_seconds :int` · `source [:livekit_webhook,:manual]` · timestamps.
Индексы: `unique(meeting_id, user_id)`, `(org_id, user_id)`, `(meeting_id, status)`.

### meeting_recordings (D-009)
`id` · `org_id` · `meeting_id` · `egress_id` · `storage_path` · `encrypted :boolean` · `started_at` · `ended_at (nullable)` · `requested_by →users` · timestamps.

## Расчёт статусов (D-008)
Пороги из `meetings.late_threshold_seconds` (E1) и `scheduled_start/end`.
- **present:** `joined_at ≤ scheduled_start + late_threshold`.
- **late:** `joined_at > scheduled_start + late_threshold`.
- **left_early:** `left_at < scheduled_end` (минус допуск).
- **absent:** invitee с `expected=true`, но НЕТ записи с `joined_at` — вычисляется при завершении встречи.
- **Ad-hoc** (D-008): записи создаются по факту входа, **без `absent`** (нет ожидаемого списка).

## Обработка webhooks (из E1) → attendance
- `participant_joined` → upsert `attendance_record`: `joined_at`, статус present/late по времени. Идемпотентно (по `meeting_id+user_id`).
- `participant_left` → update: `left_at`, прибавить `total_seconds`; пометить `left_early` если рано. (Повторные join/leave — суммируем длительность.)
- `room_finished` → **Oban-джоба** `Svc.Attendance.FinalizeWorker`: для каждого `meeting_invitee(expected:true)` без `joined_at` → `attendance_record(status: :absent)`. Идемпотентно.

## Серверная запись (D-009) — `Svc.Recordings`
- При `room_started`, если `meeting.recording_policy ∈ [:optional(вкл),:required]` → `Svc.LiveKit` стартует **Egress** (RoomComposite/Track) → storage.
- Хранение **encrypted at-rest** (AES-256, D-010). `recording_policy=off` → Egress НЕ стартует.
- Доступ к записи — по RBAC (E0) + `Svc.Audit.log(:recording_access)`.

## Профиль / enrollment (Фото/ФИО/Номер)
- ФИО/Номер — поля users (E0). **Фото:** загрузка Admin/HR при заведении (`photo_path`), хранится шифрованно (это биометрия → ПДн, см. `docs/security/compliance.md`). Используется позже для face-match (E6).
- LiveView-форма enrollment (валидация, превью фото).

## Журнал-UI (LiveView, apps/svc_web)
- Список встреч → детали встречи → **таблица посещаемости** (Фото · ФИО · статус · joined/left · длительность).
- **RBAC-scoped** (E0 `Svc.Authz`): manager — только свой отдел+поддерево; admin/security_officer — вся org.
- Фильтры (по сотруднику/отделу/периоду), сводка (present/late/absent counts).
- Экспорт (CSV/PDF) → `Svc.Audit.log(:journal.export)`.
- Просмотр журнала → `Svc.Audit.log(:journal.view)` (D-014).

## Тесты (TDD)
- `Svc.Attendance`: расчёт статусов (present/late/left_early на граничных временах); absent через Finalize; гибрид (ad-hoc без absent); идемпотентность webhook-обработки (повторные joined/left); суммирование длительности при re-join.
- Scoping журнала (manager не видит чужой отдел — E0 Authz).
- `Svc.Recordings`: Egress стартует только при policy≠off; запись encrypted; доступ под audit.
- `org_id`-изоляция (D-005).

## Acceptance criteria
1. Организатор создаёт встречу с **ростером** (из сотрудников/отдела) — E1+E2.
2. 2 сотрудника заходят (Tauri), 1 опаздывает, 1 из ростера не приходит.
3. После встречи журнал показывает: present / late / **absent** корректно.
4. Manager видит журнал **только своего отдела**.
5. Ad-hoc встреча даёт факт-лог без absent.
6. При `recording_policy≠off` запись создаётся, шифруется, доступ логируется.
7. Профиль с Фото/ФИО/Номер заведён и виден в журнале.

## Открытые вопросы
- Допуск left_early (сколько секунд до конца считать «ушёл раньше»).
- Частичное присутствие (вошёл на 5 мин из часа) — отдельный статус или по total_seconds?
- Формат экспорта журнала для гос (PDF с подписью? CSV?).
- Срок хранения записей/журналов (комплаенс — `docs/security/compliance.md`).
- Хранилище записей (S3-совместимое on-prem? MinIO?).
