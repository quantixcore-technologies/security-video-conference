# Current Status — Security Video Conference

> Обновлять в конце каждой сессии. Снимок состояния для следующего агента/сессии.

## Фаза: 0 — Документация + каркас (почти завершена)

### Сессия 2026-06-05 (S1) — Брейншторм + Фаза 0
**Сделано:**
- ✅ Брейншторм (superpowers). 14 решений → [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md).
- ✅ Разведка 4 отрядов → [research/](research/) (ML-стек, anti-capture, LiveKit/E2EE, desktop).
- ✅ Мастер-план E0–E7 утверждён → `~/.claude/plans/security-video-conference-zoom-serene-perlis.md`.
- ✅ Документация: README, ROADMAP, ARCHITECTURE, ADR, CURRENT_STATUS, CLAUDE.md.
- ✅ Security-доки: SECURITY (threat model), encryption, anti-capture-matrix, compliance (каркас).
- ✅ Спеки **всех 8 эпиков** E0–E7 ([superpowers/specs/](superpowers/specs/)). E0/E1/E2 — детально; E3–E7 — план-спеки.
- ✅ **Scaffold Phoenix umbrella компилируется:** `apps/svc` (core) + `apps/svc_web`.
- ✅ Боевые deps в `svc`: livekitex 0.1.34, argon2_elixir 4.1, nimble_totp 1.0, oban 2.23, bodyguard 2.4.
- ✅ Фикс: protobuf override 0.16.1 (livekitex несовместим с Elixir 1.19/OTP 28 без него).
- ✅ Коммиты: 9363564 (docs), 021bebf (scaffold+security), df055cb (specs) + naming-fix.

**Окружение:** Elixir 1.19.5/OTP 28 · Rust 1.93 · Node 25 · Docker 29 · Git 2.50 (psql нет → Postgres через Docker).

**Структура (фактическая):** `apps/svc` (core: contexts+Repo+schemas, модули `Svc.*`) + `apps/svc_web` (LiveView/API, `SvcWeb.*`). Tauri-клиент → `desktop/` (ещё нет). ML → `ml_service/` (E6).

**Git:** локальный, **без remote** (push ждёт команды Otabek). Вопрос: remote на `git.n3xt.uz`?

### Следующие шаги (Фаза 0 → 0.5 → 1)
1. Конфиг: Oban в `Svc.Application` + очереди; `config/runtime.exs` (LiveKit env, ключ шифрования).
2. `deploy/`: docker-compose (LiveKit/Postgres/Redis/coTURN локально) + helm values (K8s).
3. **🔬 Фаза 0.5 — PoC-спайк:** Tauri+WebView2+LiveKit JS на Windows (камера/мик/screen-share + setContentProtected). De-risk. **Требует Windows-машину** (192.168.0.115 / их парк).
4. **Фаза 1 (E0)** по [specs/E0-foundation.md](superpowers/specs/E0-foundation.md): TDD — миграции (orgs/departments/users/audit) → контексты `Svc.Orgs`/`Svc.Accounts`/`Svc.Authz`/`Svc.Audit` → auth+TOTP → RBAC scoping → LiveView админка.

### Открытые вопросы заказчику
Комплаенс (O'zDSt/СКЗИ — см. [security/compliance.md](security/compliance.md)) · парк Windows-версий · каналы уведомлений E3 · смысл «CRM» (E4, блокер) · mobile-стек фазы 2 · OneID/E-IMZO задел · политика хранения записей.
