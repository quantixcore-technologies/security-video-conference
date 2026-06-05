# E0 — Фундамент + Аудит/Комплаенс (детальный спек)

> **Статус:** Срез 1, Фаза 1 — детальный спек к реализации. Закон: foundation overkill (D-014).
> **ТЗ:** RBAC, Maximal Data Security, Защищённый канал. **Зависит:** — (базовый эпик).
> Версии библиотек проверять через Context7/`mix hex.info` (NET-SCAN-01).

## Цель
Безопасный каркас платформы: организации с иерархией отделов, пользователи (сотрудники) с профилем и аутентификацией (пароль + 2FA), RBAC с department-scoping, сквозной audit-log. На этом стоят все остальные эпики.

## Контексты (apps/svc)
- **`Svc.Orgs`** — organizations, departments (иерархия).
- **`Svc.Accounts`** — users, аутентификация (пароль Argon2id, TOTP), сессии.
- **`Svc.Authz`** — RBAC-политики (Bodyguard), department-scoping.
- **`Svc.Audit`** — audit_log (сквозной).

## Доменные сущности (Ecto, все с `org_id` — D-005)

### organizations
`id` · `name` · `slug` · `settings :map` · `status [:active,:suspended]` · timestamps.

### departments (иерархия через self-ref)
`id` · `org_id →organizations` · `parent_id →departments (nullable)` · `name` · `head_user_id →users (nullable)` · timestamps.
Индексы: `(org_id)`, `(parent_id)`. Запрос поддерева — рекурсивный CTE (`WITH RECURSIVE`).

### users
`id` · `org_id` · `department_id (nullable)` · `username :citext` (уникален в org) · `hashed_password` (Argon2id) · `full_name` (ФИО) · `phone` (Номер) · `photo_path (nullable)` (Фото) · `role [:super_admin,:admin_hr,:manager,:employee,:security_officer]` · `totp_secret (nullable, encrypted)` · `totp_enabled :boolean` · `status [:active,:disabled]` · `last_login_at` · `failed_attempts :int` · `locked_until` · timestamps.
Индексы: `unique(org_id, username)`, `(org_id, department_id)`, `(org_id, role)`.

### audit_logs
`id` · `org_id` · `actor_user_id (nullable)` · `action :string` (`login.success`, `user.create`, `role.change`, `journal.view`, `recording.access`, …) · `resource_type` · `resource_id` · `metadata :map` · `ip :string` · `user_agent :string` · `inserted_at`.
Индексы: `(org_id, inserted_at)`, `(actor_user_id)`, `(resource_type, resource_id)`. **Только append** (без update/delete).

## Миграции (порядок)
1. `enable citext` extension.
2. create organizations.
3. create departments (FK org, self-ref parent).
4. create users (FK org, department; enum role/status).
5. create audit_logs.
6. create oban_jobs (Oban migration).

## Аутентификация (D-006)
1. **Создание:** `Svc.Accounts.create_user/2` (только Admin/HR через UI) — задаёт ФИО/username/телефон/фото/роль/отдел + временный пароль.
2. **Пароль:** Argon2id (`argon2_elixir`). `authenticate(org, username, pass)` — постоянное время (Argon2 no_user_verify при отсутствии). Rate-limit + `failed_attempts`/`locked_until` (блокировка после N).
3. **2FA (TOTP, `nimble_totp`):** enrollment — генерим `totp_secret` (шифруем at-rest), отдаём otpauth-URI → QR. Verify-код активирует `totp_enabled`. Вход: пароль → если `totp_enabled`, требуем TOTP-код (окно ±1). **Обязателен** для super_admin/admin_hr/manager/security_officer; для employee — по политике org.
4. **Сессии:** Phoenix `live_session` + signed session token; idle-timeout; `last_login_at`; audit `login.success/failure`.

## RBAC (D-007) — `Svc.Authz` на Bodyguard
- Роли (см. enum). Политики per-context: `Svc.Accounts.Policy`, `Svc.Orgs.Policy` и т.д.
- **Department-scoping:** `Svc.Authz.visible_user_ids(actor)` →
  - super_admin/admin_hr/security_officer → вся org;
  - manager → свой `department_id` + всё поддерево (рекурсивный CTE);
  - employee → только сам.
- Все запросы списков/журналов проходят через scoping-хелпер. `org_id`-scoping — всегда (D-005).

## Audit (D-014) — `Svc.Audit`
- `Svc.Audit.log(actor, action, opts)` — пишет audit_log (actor, action, resource, metadata, ip, ua).
- Обязательно логируем: входы (успех/провал), CRUD пользователей/отделов, смену ролей, просмотр журналов посещаемости (E2), доступ к записям (E2). Append-only.
- Plug `Svc.Web.AuditContext` — прокидывает ip/user_agent в процесс.

## Конфигурация
- `config/runtime.exs`: DB, `SECRET_KEY_BASE`, ключ шифрования полей (TOTP-секрет/фото), Oban-очереди. Секреты из env (D: не в git).
- Oban в `Svc.Application` (очереди: `default`, `attendance`, `notifications`(E3)).

## Тесты (TDD — вперёд кода)
- `Svc.Orgs`: создание org/department; рекурсивный subtree; запрет цикла в иерархии.
- `Svc.Accounts`: create_user (валидация ФИО/username уникальность в org); authenticate (верный/неверный пароль; постоянное время); блокировка после N попыток; TOTP enroll + verify; обязательность 2FA по роли.
- `Svc.Authz`: scoping — manager видит только своё поддерево; employee только себя; admin всю org; кросс-org изоляция (D-005).
- `Svc.Audit`: log пишет запись; append-only; чувствительные действия логируются.

## Acceptance criteria
1. Admin/HR создаёт сотрудника с ФИО/Фото/Номер/ролью/отделом.
2. Сотрудник входит: пароль (Argon2id) + TOTP-код.
3. Manager в админке видит сотрудников **только своего отдела+поддерева**, не чужих.
4. Кросс-org доступа нет (org_id-изоляция).
5. Все чувствительные действия → audit_logs (append-only).
6. Секреты (TOTP/ключи) зашифрованы at-rest, не в git.

## Открытые вопросы
- Политика паролей (длина/сложность/ротация) — уточнить у заказчика (комплаенс).
- Idle/absolute session timeout — значения по гос-требованиям.
- Шифрование полей: app-level (Cloak) vs Postgres TDE — выбрать на старте E0.
- Hook для будущей OneID/E-IMZO интеграции (D-006) — заложить интерфейс провайдера аутентификации.
