# Current Status — Security Video Conference

> Обновлять в конце каждой сессии. Снимок состояния для следующего агента/сессии.

## Прогресс: E0 ✅ · E1-backend ✅ · E2-backend ✅ (Срез 1 backend готов)

### Сессия 2026-06-05 (S1) — Брейншторм + Срез 1 backend целиком
**Сделано:**
- ✅ Дизайн: брейншторм, 14 ADR, мастер-план E0–E7, разведка 4 отрядов.
- ✅ Документация: 19 доков + 8 эпик-спеков.
- ✅ **E0 Фундамент** (5 слайсов): Orgs, Accounts (Argon2+TOTP), Authz (RBAC), Audit, LiveView-админка.
- ✅ **E1 Ядро конференций — backend** (3 слайса): Meetings, LiveKit (JWT), webhook + join API.
- ✅ **E2 Посещаемость — backend** (3 слайса): Attendance (ростер+журнал+статусы), Oban FinalizeWorker, Recordings (Egress-сущность).
- ✅ **99 тестов, 0 failures.** 16 коммитов, запушено на git.n3xt.uz/legion-cyber-arena (private).

**Окружение:** Elixir 1.19.5/OTP 28 · Rust 1.93 · Node 25 · Docker 29.
**⚠️ Локально:** Postgres docker `svc-postgres` на **5434**. Префикс `DB_PORT=5434` для mix-команд.
**Oban:** версия **14** (не 12 — Oban 2.23 требует v14).

### TODO / не закрыто (для следующих слоёв)
- **Журнал-UI** (LiveView таблица посещаемости) — backend готов, UI нет.
- **Tauri-клиент** + PoC-спайк — требует Windows-машину.
- **Реальный LiveKit Egress-вызов** (Recordings.start_recording) — TODO, требует LiveKit running.
- **Инфра:** docker-compose LiveKit (server/coTURN) + config dev/runtime LiveKit env — для E2E видеозвонка.
- Фото-upload UI (E2 enrollment), шифрование totp_secret (Cloak), политика паролей (заказчик).

### Следующие шаги (на выбор)
1. **Журнал-UI** (LiveView) — видимый результат посещаемости в админке (RBAC-scoped).
2. **Tauri-клиент** (desktop/) — нужен Windows для теста.
3. **Инфра LiveKit** (docker-compose) — запустить реальный видеозвонок end-to-end.
4. Перейти к E3 (планирование/уведомления) или security-эпикам (E5/E6/E7).

### Открытые вопросы заказчику
Комплаенс O'zDSt/СКЗИ · парк Windows · каналы уведомлений E3 · смысл «CRM» (E4) · mobile-стек · OneID/E-IMZO · хранение записей.
