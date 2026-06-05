# Архитектура системы — Security Video Conference

> Решения: [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md). Разведка: [research/](research/).

## Компоненты

```
КЛИЕНТЫ:
  • Tauri Desktop (Windows-first): Rust shell + WebView2 + LiveKit JS   ← видеоконференция
       └ setContentProtected(true), [E5: детект рекордеров / watermark / kiosk / TPM]
  • Web (Phoenix LiveView): админка / журналы / планирование — БЕЗ видео ← управление
        │ HTTPS/WSS (REST+JSON / LiveView)         │ WebRTC (DTLS-SRTP, hop-by-hop)
        ▼                                          ▼
  ┌─────────────────────────────────────┐   ┌──────────────────────────────┐
  │ Phoenix umbrella (on-prem)          │   │ LiveKit (self-host, K8s)     │
  │  • svc_web: LiveView, JSON API,     │◄──┤  • livekit-server (SFU)      │
  │      /webhooks/livekit              │   │  • Redis, coTURN             │
  │  • svc (core): contexts (Accounts/  │   │  • [E2: Egress — опц.запись] │
  │      Orgs/Meetings/Attendance/      │   │  • [E6: Agents — ML-кадры]   │
  │      Audit), Repo, livekitex,       │   │     webhooks ──────────────► │
  │      Presence, Oban                 │   └──────────────────────────────┘
  │                                     │
  │            │ Ecto                    │   ┌──────────────────────────────┐
  │            ▼                          │   │ ML-сервис (E6, GPU)          │
  │   PostgreSQL (org_id-scoped,        │◄──┤  Python (FastAPI) + Rust(ort)│
  │     at-rest шифр.)                   │   │  face-match/liveness/deepfake│
  └─────────────────────────────────────┘   └──────────────────────────────┘
```

**Принцип:** медиа идёт напрямую клиент↔LiveKit (DTLS-SRTP); Phoenix в медиа-тракте НЕ участвует — только управление (JWT-токены, приём webhooks). ML получает кадры server-side через Egress/Agents (E2EE off — D-010).

## Слои umbrella (фактическая структура: `apps/svc` + `apps/svc_web`)
- **svc** (core) — `Repo`, Ecto-схемы/миграции + бизнес-домен: contexts `Accounts`, `Orgs`, `Meetings`, `Attendance`, `Audit`; интеграция LiveKit (`livekitex`); `Presence`; `Oban`-воркеры. Не знает про web. Модули — `Svc.*`.
- **svc_web** — Phoenix endpoint: LiveView админка (без видео), JSON API для Tauri, `/webhooks/livekit`, auth-плаги. Зависит от core. Модули — `SvcWeb.*`.

## Потоки (Срез 1)
1. **Auth+2FA:** админ создаёт user → пароль (Argon2id) → TOTP enrollment (`nimble_totp`) → вход пароль+TOTP. Session-timeout, rate-limit, audit.
2. **Создать встречу:** organizer → `meeting(planned)` + `meeting_invitees` (ростер).
3. **Войти (Tauri):** join → Phoenix RBAC+ростер-чек → `livekitex` JWT → Tauri+LiveKit JS → `setContentProtected(true)` → A/V.
4. **Посещаемость:** LiveKit webhooks (joined/left) → HMAC-проверка → `attendance_records`; статусы present/late/left_early/absent (Oban при завершении).
5. **Опц. запись:** `recording_policy≠off` → Egress → encrypted storage → `meeting_recordings` (RBAC+audit).

## Encryption posture (D-010)
| Слой | Защита |
|------|--------|
| Медиа in-transit | DTLS-SRTP (hop-by-hop, сервер доверенный) |
| At-rest | Postgres диск-шифр + app-level для фото/записей (AES-256) |
| Control (signaling/API/webhooks) | TLS 1.2+ |
| E2EE participant-to-participant | ❌ off (несовместимо с серверным ML) |

## Deployment
- Kubernetes (2-node on-prem, RTX 4060 Ti на нодах). ArgoCD (GitOps).
- LiveKit: host-networking, 1 SFU/нода, Redis, coTURN, [Egress/Agents].
- Phoenix: releases, runtime-config (секреты из env/Vault).
- ML-сервис (E6): отдельный pod на GPU-ноде.

## Безопасность (foundation overkill — D-014)
RBAC 4+1 роли + department-scoping (рекурсия `parent_id`) · сквозной audit-log · `org_id`-изоляция · секреты вне git · Argon2id · TOTP · rate-limit.
