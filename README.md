# Security Video Conference (SVC)

> Защищённая видеоконференц-платформа для контроля сотрудников и посещаемости. **B2G (Узбекистан).**
> Команда: Furqat / Shuxrat / Otabek. Закон проекта: **«На Foundation не бывает Overkill».**

## Что это

Secure Zoom-class платформа: видеоконференции с жёстким контролем присутствия («кто был / кто отсутствовал»), защитой контента (запрет скриншота/записи), подтверждением реальности участника (анти-DeepFake/liveness), контролем сети (VPN/гео) и максимальной приватностью данных (self-host, on-prem).

«Zoom-форк» = строим Zoom-класс на **LiveKit** (Zoom не open-source), а не форкаем Zoom буквально.

## Стек

| Слой | Технология |
|------|-----------|
| Backend-ядро | Elixir / Phoenix umbrella (`svc_core` / `svc_web` / `svc_shared`) |
| БД | PostgreSQL (Ecto, `org_id`-scoped) |
| Медиа (SFU) | LiveKit (self-host, K8s) — hop-by-hop DTLS-SRTP |
| Desktop-клиент | **Tauri** (Rust + WebView2 + LiveKit JS) — Windows-first |
| Web | Phoenix LiveView (управление, БЕЗ видео) |
| ML-сервис (E6) | Python + Rust (`ort`/ONNX) — face-match / liveness / deepfake |
| Net/Geo (E7) | MaxMind GeoIP2 + Locus (self-host) |
| Deploy | Docker · Kubernetes (on-prem) · ArgoCD |

## Карта эпиков

```
E0 Фундамент+Аудит ──► E1 Ядро ──► E2 Посещаемость   ◄── Срез 1 / Milestone 1
                                     ├──► E3 Планирование+Уведомления ──► E4 CRM+Kanban
                                     └──► E5 Анти-захват · E6 Реальность(ML) · E7 Сеть+Гео
```

Подробно: [docs/ROADMAP.md](docs/ROADMAP.md).

## Документация

- [docs/ROADMAP.md](docs/ROADMAP.md) — дорожная карта фаз E0–E7
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — архитектура системы
- [docs/ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md) — ADR (14 решений)
- [docs/CURRENT_STATUS.md](docs/CURRENT_STATUS.md) — текущий статус
- [docs/superpowers/specs/](docs/superpowers/specs/) — спеки эпиков
- [docs/security/](docs/security/) — security posture, encryption, anti-capture-матрица, compliance
- [docs/research/](docs/research/) — разведка (ML-стек, anti-capture, LiveKit, desktop)
- [docs/runbooks/](docs/runbooks/) — деплой LiveKit/ML

## Статус

🚧 **Фаза 0** — документация + каркас. Greenfield. См. [docs/CURRENT_STATUS.md](docs/CURRENT_STATUS.md).
