# E1 — Ядро конференций (детальный спек)

> **Статус:** Срез 1, Фаза 2 — детальный спек. **ТЗ:** Video Conference, Защищённый канал.
> **Зависит:** E0 (users/auth/RBAC). **Риск:** LiveKit+WebView2 (MODERATE) → PoC-спайк ПЕРВЫМ.
> Версии — через Context7 (NET-SCAN-01).

## Цель
Рабочая видеосвязь: организатор создаёт встречу, авторизованные пользователи входят с **Tauri-клиента**, получают A/V через LiveKit (hop-by-hop DTLS-SRTP, D-010). Phoenix управляет (JWT-токены, приём webhooks), но НЕ в медиа-тракте.

## Компоненты
- **LiveKit self-host** (D-003): helm на K8s + docker-compose локально (server, Redis, coTURN).
- **`Svc.Meetings`** (apps/svc): meetings CRUD, генерация join-токена.
- **`Svc.LiveKit`** (apps/svc): обёртка над `livekitex` — JWT (AccessToken), RoomService (create/list/removeParticipant), верификация webhook-подписи.
- **`SvcWeb` API + webhook** (apps/svc_web): JSON API для Tauri (`POST /api/meetings/:id/join` → token), `POST /webhooks/livekit` (HMAC-проверка).
- **Tauri-клиент** (desktop/): Rust shell + WebView2 + LiveKit JS.

## Доменные сущности (Ecto, `org_id`)

### meetings
`id` · `org_id` · `title` · `type [:scheduled,:ad_hoc]` · `scheduled_start (nullable)` · `scheduled_end (nullable)` · `status [:planned,:live,:ended]` · `livekit_room_name` (уникален) · `organizer_id →users` · `recording_policy [:off,:optional,:required]` (D-009) · `late_threshold_seconds :int` (для E2) · timestamps.
Индексы: `(org_id, status)`, `unique(livekit_room_name)`, `(organizer_id)`.

> Ростер (`meeting_invitees`) и журнал (`attendance_records`) — в E2. В E1 join разрешён авторизованным из org по RBAC; строгая сверка с ростером добавляется в E2.

## LiveKit-интеграция (`Svc.LiveKit` через livekitex)
- **JWT join-токен:** `AccessToken.new(api_key, api_secret) |> with_identity("user-#{id}") |> with_name(full_name) |> with_grants(room_join: room, can_publish: true, can_subscribe: true) |> with_ttl(...)`. HS256 (D: симметричный ключ из env).
- **RoomService (REST/Twirp через Finch/req):** CreateRoom при старте встречи, RemoveParticipant (модерация), ListParticipants.
- **Webhooks:** `POST /webhooks/livekit` — читать **raw body ДО парсинга**, проверить HMAC-SHA256 (`Authorization`). События `room_started`, `participant_joined/left`, `room_finished`. В E1 — приём+верификация+лог; обработка в attendance — E2.

## Tauri-клиент (desktop/)
```
desktop/
├── src-tauri/        # Rust shell
│   ├── src/main.rs   # окно + setContentProtected(true) при старте
│   └── tauri.conf.json
└── src/              # WebView2 frontend (React/Svelte) + LiveKit JS
    ├── livekit.ts    # connect(room, token) → A/V, track rendering
    └── App.*
```
- **Анти-захват baseline:** `app.get_webview_window().set_content_protected(true)` (D-002/D-013) — Win32 `SetWindowDisplayAffinity`. (Детект рекордеров/watermark — E5.)
- **Join-флоу:** auth к Phoenix (E0) → `POST /api/meetings/:id/join` → `{ livekit_url, token }` → LiveKit JS `room.connect(url, token)` → publish камера/мик, subscribe remote tracks.

## 🔬 PoC-спайк (Фаза 0.5 — ДО полной разработки, de-risk MODERATE-риска)
Минимальный Tauri + LiveKit JS на **Windows**:
1. `cargo create-tauri-app`, окно + `set_content_protected(true)`.
2. LiveKit JS подключается к локальному LiveKit (docker), publish камера/мик, 2 участника видят друг друга, screen-share.
3. Проверить: getUserMedia в WebView2 (разрешения камеры/мик); скриншот окна = чёрный.
**Если RISKY** (WebView2 ломает WebRTC) → fallback Electron + самостоятельный патч #47834. Решение фиксируется как ADR.

## Конфигурация
- `config/runtime.exs`: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WEBHOOK_KEY` (из env).
- `deploy/`: docker-compose (local LiveKit/Redis/coTURN), helm values (K8s, host-networking, 1 SFU/нода).

## Тесты (TDD)
- `Svc.Meetings`: create/list/get; уникальность room_name; RBAC (кто может создать).
- `Svc.LiveKit`: генерация JWT (claims/grants корректны); верификация webhook HMAC (валид/невалид/replay).
- `SvcWeb`: `/api/meetings/:id/join` — авторизация (E0), отдаёт токен только разрешённым; webhook endpoint — 401 на плохой подписи.
- Tauri — ручная проверка по PoC-чеклисту (camera/mic/screen-share/content-protection).

## Acceptance criteria
1. Организатор создаёт встречу (web-админка), получает LiveKit room.
2. 2 пользователя входят с Tauri-клиента, видят/слышат друг друга (A/V).
3. Канал — DTLS-SRTP (E2EE off, D-010).
4. `setContentProtected` активен: скриншот окна Tauri = чёрный (на Windows).
5. LiveKit webhooks приходят в Phoenix, подпись проверяется, логируются.
6. Join-токен выдаётся только авторизованным (RBAC E0); неавторизованный получает 403.

## Открытые вопросы
- UI-фреймворк фронта Tauri (React vs Svelte) — решить на PoC.
- coTURN-конфиг под их сеть (NAT/firewall гос-инфраструктуры).
- Лимит участников на встречу (сайзинг SFU).
- Реакция на падение webhook (ретраи LiveKit) — идемпотентность приёма.
