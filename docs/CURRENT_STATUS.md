# Current Status — Security Video Conference

> Обновлять в конце каждой сессии. Снимок состояния для следующего агента/сессии.

## Фаза: 0 — Документация + каркас (в работе)

### Сессия 2026-06-05 (S1) — Брейншторм + старт Фазы 0
**Сделано:**
- ✅ Брейншторм проведён (superpowers). 14 решений зафиксированы → [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md).
- ✅ Разведка 4 отрядов (ML-стек, anti-capture, LiveKit self-host/E2EE, desktop-фреймворк) → [research/](research/).
- ✅ Мастер-план E0–E7 утверждён → `~/.claude/plans/security-video-conference-zoom-serene-perlis.md`.
- ✅ Структура `docs/` создана.
- ✅ Корневые доки: README, ROADMAP, ARCHITECTURE, ARCHITECTURE_DECISIONS, .gitignore.
- 🚧 В работе: project CLAUDE.md, security-доки, эпик-спеки E0–E7, git init.

**Окружение:** Elixir 1.19.5/OTP 28 · Rust 1.93 · Node 25 · Docker 29 · Git 2.50 (psql нет — Postgres через Docker).

**Ключевые решения (кратко):** Phoenix umbrella · LiveKit self-host · Tauri desktop · single-tenant+org_id · Argon2id+TOTP · RBAC 4+1+scoping · посещаемость-гибрид · опц.запись · E2EE off (hop-by-hop) · ML=Python+Rust · MaxMind+Locus · foundation overkill.

### Следующие шаги (Фаза 0 → 0.5)
1. Завершить документацию (CLAUDE.md, security/*, specs/E0–E7).
2. git init + первый commit.
3. Scaffold Phoenix umbrella (`svc_core`/`svc_web`/`svc_shared`) + Postgres + Oban.
4. LiveKit локально (docker-compose) + helm на K8s.
5. **🔬 PoC-спайк:** Tauri+WebView2+LiveKit JS на Windows (камера/мик/screen-share + setContentProtected) — de-risk.
6. → Фаза 1 (E0): Accounts, auth+TOTP, RBAC, audit.

### Открытые вопросы заказчику
Комплаенс (O'zDSt/СКЗИ) · парк Windows-версий · каналы уведомлений E3 · смысл «CRM» (E4) · mobile-стек фазы 2 · OneID/E-IMZO в будущем · политика хранения записей.
