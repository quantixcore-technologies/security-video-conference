# Current Status — Security Video Conference

> Обновлять в конце каждой сессии. Снимок состояния для следующего агента/сессии.

## Фаза: 1 (E0) ЗАВЕРШЕНА ✅ → следующая Фаза 2 (E1)

### Сессия 2026-06-05 (S1) — Брейншторм + Фаза 0 + E0 целиком
**Сделано:**
- ✅ Брейншторм (14 ADR), мастер-план E0–E7, разведка 4 отрядов.
- ✅ Документация: 19 доков (README/ROADMAP/ARCHITECTURE/security/specs/research).
- ✅ Scaffold Phoenix umbrella (`svc` + `svc_web`), 5 боевых библиотек, protobuf override.
- ✅ **E0 Фундамент — 5 слайсов, 55 тестов, 0 failures:**
  - 1.1 `Svc.Orgs` — организации + иерархия отделов (рекурсивный CTE) + org-изоляция
  - 1.2 `Svc.Accounts` — auth Argon2id + TOTP 2FA + lockout
  - 1.3 `Svc.Authz` — RBAC department-scoping
  - 1.4 `Svc.Audit` — append-only audit-log
  - 1.5 LiveView админка — login(пароль→TOTP), dashboard, users CRUD (RBAC в UI)
- ✅ 9 коммитов (локально, без remote).

**Окружение:** Elixir 1.19.5/OTP 28 · Rust 1.93 · Node 25 · Docker 29.
**⚠️ Локально:** Postgres в docker `svc-postgres` на **5434** (brew-postgres@17 на 5432). Префикс `DB_PORT=5434`.

### ⚠️ TODO из E0 (честно — не закрыто, для следующих слоёв)
- **Фото-upload UI** (enrollment Фото) — поле `photo_path` есть, загрузка файла → E2 (enrollment).
- **Шифрование `totp_secret` at-rest** (app-level Cloak) — сейчас raw binary. → слой хардненинга.
- **Политика паролей** (точные требования) — у заказчика (комплаенс).
- Git remote `git.n3xt.uz` — Otabek подтвердил Gitea, ждёт namespace для добавления remote.

### Следующие шаги (Фаза 2 = E1, см. specs/E1-conferencing-core.md)
1. **🔬 PoC-спайк** Tauri+WebView2+LiveKit JS на Windows (de-risk MODERATE) — требует Windows-машину.
2. LiveKit self-host: docker-compose локально (server/Redis/coTURN) — инфра-агенты.
3. `Svc.Meetings` context + `Svc.LiveKit` (livekitex: JWT, RoomService, webhooks).
4. Webhook endpoint `/webhooks/livekit` (HMAC).
5. Tauri-клиент: join + A/V + setContentProtected.

### Открытые вопросы заказчику
Комплаенс O'zDSt/СКЗИ · парк Windows · каналы уведомлений E3 · смысл «CRM» (E4) · mobile-стек · OneID/E-IMZO задел · хранение записей.
