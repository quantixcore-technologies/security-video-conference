# Current Status — Security Video Conference

> Обновлять в конце каждой сессии. Снимок состояния для следующего агента/сессии.

## Срез 1 ПОЛНОСТЬЮ ГОТОВ и работает вживую ✅ (E0+E1+E2+UI+LiveKit+полировка)

### Сессия 2026-06-05 (S1) — с нуля до живого Среза 1
**Построено и доказано вживую:**
- ✅ Дизайн: 14 ADR, мастер-план E0–E7, разведка 4 отрядов, 19 доков + 8 спеков.
- ✅ **E0** Фундамент: Orgs, Accounts (Argon2+TOTP), Authz (RBAC), Audit, LiveView-админка.
- ✅ **E1** Ядро: Meetings, LiveKit (JWT), webhook, join-API, **живой видеозвонок** (docker LiveKit).
- ✅ **E2** Посещаемость: ростер, журнал (статусы), Oban, записи (Egress-сущность), **журнал-UI**.
- ✅ **Полировка:** SVC-navbar, фото-upload (enrollment), **totp_secret шифрование at-rest (Cloak)**.
- ✅ **104 теста, 0 failures.** 22 коммита на git.n3xt.uz/legion-cyber-arena (private).
- ✅ **Проверено в браузере:** login→dashboard→встречи→журнал; реальный звонок → webhook → авто-attendance.

**Окружение:** Elixir 1.19.5/OTP 28 · Rust 1.93 · Node 25 · Docker 29.
**⚠️ Локально:** Postgres docker `svc-postgres` :5434 (`DB_PORT=5434`). LiveKit docker :7880
(`docker compose -f deploy/livekit/docker-compose.yml up -d`). phx.server :4000 (`admin`/`AdminPass12345`).
**Oban v14. Cloak dev-key — в prod из env `CLOAK_KEY`.**

### Что НЕ сделано (следующие фазы)
- **Tauri-клиент** (prod-видео с anti-capture, требует Windows). DEV-звонок пока через браузер `/admin/meetings/:id/call`.
- **Реальный LiveKit Egress** (запись) — TODO (сущность есть).
- **E3** планирование/уведомления · **E4** CRM/Kanban · **E5** анти-захват · **E6** ML-liveness · **E7** сеть/гео.

### Команды
```
docker compose -f deploy/livekit/docker-compose.yml up -d   # LiveKit
DB_PORT=5434 mix phx.server                                  # Phoenix
DB_PORT=5434 mix test                                        # тесты
DB_PORT=5434 mix run apps/svc/priv/repo/seeds.exs            # демо-данные
```

### Открытые вопросы заказчику
Комплаенс O'zDSt/СКЗИ · парк Windows · каналы уведомлений E3 · смысл «CRM» (E4) · mobile-стек · OneID/E-IMZO.
