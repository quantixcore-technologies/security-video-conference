# CLAUDE.md — Security Video Conference (навигация для агентов)

> Проект-level вход. Глобальные законы — в `~/.claude/CLAUDE.md`. Этот файл — про ЭТОТ проект.

## Что это
B2G (Узбекистан) secure видеоконференц-платформа. Команда: Furqat / Shuxrat / Otabek.
**Закон проекта: «На Foundation не бывает Overkill».**

## Старт сессии (читать по порядку)
1. [docs/CURRENT_STATUS.md](docs/CURRENT_STATUS.md) — где остановились
2. [docs/ROADMAP.md](docs/ROADMAP.md) — фазы E0–E7
3. [docs/ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md) — 14 ADR (почему так)
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — компоненты/потоки
5. [docs/research/](docs/research/) — разведка (читать перед security-эпиками)

## Стек (НЕ гадать версии — Context7 / `mix hex.info`)
Elixir/Phoenix umbrella (`svc` core + `svc_web`) · PostgreSQL/Ecto · LiveKit self-host · Tauri desktop (Rust+WebView2+LiveKit JS) · LiveView web (без видео) · Python+Rust ML (E6) · MaxMind+Locus (E7) · K8s/ArgoCD.

## Ключевые библиотеки
`livekitex` (LiveKit SDK) · `argon2_elixir` · `nimble_totp` · `oban` · `finch` · `locus` (E7).

## Команды (после scaffold)
```bash
# ⚠️ Локально: docker-Postgres `svc-postgres` на порту 5434
#    (хостовый brew postgresql@17 занимает 5432). Префикс DB_PORT=5434.
#    CI/prod: дефолт 5432 (config env-based: DB_PORT/DB_HOST).
#    docker run -d --name svc-postgres -e POSTGRES_PASSWORD=postgres \
#      -e POSTGRES_USER=postgres -p 5434:5432 postgres:16
DB_PORT=5434 mix ecto.setup         # установка + БД
DB_PORT=5434 mix test               # тесты (TDD)
DB_PORT=5434 mix phx.server         # dev-сервер
cd desktop && cargo tauri dev       # Tauri-клиент (E1)
```

## Железные правила проекта
1. **Видео — только нативный клиент (Tauri).** Web = управление, БЕЗ WebRTC (D-001).
2. **E2EE off** — hop-by-hop DTLS-SRTP (сервер видит кадры для ML) (D-010).
3. **`org_id` во всех таблицах** + scoping в каждом запросе (D-005).
4. **Аудит на все чувствительные действия** (foundation overkill, D-014).
5. **Секреты НЕ в git** → env/Vault (`.gitignore` покрывает `.env`/`*.key`/`*.pfx`).
6. **Анти-захват честно:** enforce только Win/Android, аудио не запретить → watermark+политика (D-013). НЕ обещать «100% запрет».
7. **Deepfake — risk-flag, не автобан** (~78% real-world, D-011).
8. **TDD** — тесты вперёд кода. Слайс: DB→Schema→Context→Engine→UI→Tests.

## Структура
```
apps/{svc,svc_web}                  # Phoenix umbrella (svc=core: contexts+Repo+schemas)
desktop/                            # Tauri-клиент
ml_service/                         # E6 ML (Python+Rust)
deploy/                             # K8s, helm, ArgoCD
docs/                               # документация (PRIMARY по L211)
```
