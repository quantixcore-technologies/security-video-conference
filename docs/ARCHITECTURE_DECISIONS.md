# Architecture Decision Records (ADR) — Security Video Conference

> Формат: D-numbered. Каждое решение — контекст, выбор, обоснование, последствия.
> Зафиксировано на сессии брейншторма 2026-06-05 (Otabek + Клауди). Основания — разведка 4 отрядов (`docs/research/`).

---

## D-001: Платформа видео — нативный клиент, web только управление
**Контекст:** ТЗ требует enforce анти-захвата; в браузере это невозможно.
**Решение:** Видеоконференция — только нативный клиент (desktop/mobile). Web = панель управления (админка, журналы, планирование) БЕЗ видео.
**Обоснование:** убирает самую дырявую платформу из контура видео; фокусирует security-усилия туда, где enforce реален (Win/Android). См. `docs/research/anti-capture-platforms.md`.
**Последствия:** E5 упрощается; web-приложение не несёт WebRTC.

## D-002: Desktop-клиент — Tauri
**Контекст:** Windows-доминирование, max-security, LiveKit, Rust-экспертиза.
**Решение:** **Tauri** (Rust shell + WebView2 + LiveKit JS). Отвергнуты: Electron (RISKY), нативный Qt/.NET (NO-GO), Flutter Desktop (NOT READY).
**Обоснование:** `setContentProtected`→нативный Win32; LiveKit JS в WebView2; Rust-бэкенд для детекта/TPM/kiosk; 10× легче Electron. Electron анти-захват #47834 сломан на ~30-40% Windows. У LiveKit нет нативного SDK. См. `docs/research/desktop-framework.md`.
**Последствия:** PoC-спайк LiveKit+WebView2 обязателен (MODERATE risk).

## D-003: SFU — LiveKit self-host
**Решение:** LiveKit, self-host на on-prem K8s. **Обоснование:** open-source, E2EE-опция, SDK для всех платформ, Elixir SDK (`livekitex`), self-host под «Max Data Security». **Последствия:** host-networking, 1 SFU/нода, Redis, coTURN.

## D-004: Backend-ядро — Elixir/Phoenix umbrella
**Решение:** Phoenix umbrella — `svc` (core: contexts + Repo + schemas) + `svc_web` (LiveView/API). **Обоснование:** совпадает со стеком (N3XT-One); Presence=журнал посещаемости из коробки; Channels=сигналинг; PubSub=уведомления; чёткие границы под рост; «foundation overkill». **Последствия:** umbrella-церемония оправдана масштабом.

## D-005: Тенантность — single + задел на multi
**Решение:** Single-tenant, но `org_id` во всех таблицах + изоляция с дня 1. **Обоснование:** B2G (одно ведомство сейчас), но multi-ведомства/продажа без переписывания. **Последствия:** `org_id`-scoping во всех запросах.

## D-006: Auth — внутренние учётки + 2FA
**Решение:** Внутренние учётки (Argon2id) + TOTP 2FA; админ заводит сотрудников. OneID/E-IMZO — опция позже (hook). **Обоснование:** автономность, без зависимости от гос-IdP на старте; быстрый E0. **Последствия:** заложить hook для будущей гос-SSO интеграции.

## D-007: RBAC — 4+1 роли + department-scoping
**Решение:** SuperAdmin, Admin/HR, Manager, Employee + Security Officer (аудитор). Scoping по гос-иерархии (ведомство→управление→отдел через `parent_id`). **Обоснование:** «контроль сотрудников» требует иерархии (Manager видит свою команду). Granular custom-роли — эволюция. **Последствия:** рекурсивный обход иерархии для видимости.

## D-008: Посещаемость — гибрид
**Решение:** Запланированные встречи (ростер + авто-статусы present/late/absent/left_early) + ad-hoc (факт-лог без absent). **Обоснование:** «кто отсутствовал» требует ожидаемого списка; ad-hoc покрывает спонтанные созвоны. **Последствия:** Oban-джоба вычисляет absent при завершении встречи.

## D-009: Серверная запись — опционально по политике
**Решение:** По умолчанию off; организатор/политика включает per-meeting (Egress, шифр. at-rest, RBAC, audit). **Обоснование:** гос может требовать архив протокола ИЛИ запрещать — гибкость. Ортогонально «запрету записи участниками». **Последствия:** тот же Egress кормит ML (E6).

## D-010: Шифрование медиа — hop-by-hop (E2EE off)
**Контекст:** настоящий E2EE ⊥ серверный ML (анти-DeepFake).
**Решение:** E2EE **off**; hop-by-hop DTLS-SRTP (сервер доверенная точка) + at-rest AES-256 + TLS. **Обоснование:** для employer-monitoring сервер должен видеть кадры для ML; компания доверяет своим on-prem серверам. См. `docs/research/livekit-selfhost-e2ee.md`. **Последствия:** «защищённый канал» = да, но не «нулевое доверие к серверу».

## D-011: ML-стек (E6) — Python + Rust гибрид
**Решение:** Python (FastAPI, модели) + Rust (`ort`/ONNX, GPU-инференс). Face-match=InsightFace/ArcFace (приоритет, ~98%), liveness=MiniFASNet, deepfake=R&D-трек (~78%, risk-flag). **Обоснование:** 99% моделей в PyTorch (не чистый Rust); Rust для latency. См. `docs/research/ml-stack.md`. **Последствия:** deepfake НЕ продавать как 100%.

## D-012: Net/Geo (E7) — MaxMind + Locus
**Решение:** VPN-детект + гео-блок через MaxMind GeoIP2 (Anonymous IP + Country) + Elixir `locus` (self-host, без внешних API). GPS — mobile (фаза 2). **Обоснование:** «Max Data Security Private» → без внешних API. **Последствия:** GPS-функции зависят от mobile-клиента.

## D-013: Anti-capture (E5) — слоистая стратегия
**Решение:** enforce Win (`setContentProtected`)/Android (FLAG_SECURE); detect mac/iOS; видимый watermark + forensic аудио-watermark; политика. **Обоснование:** enforce невозможен везде; аудио не запретить нигде → трассировка. См. `docs/research/anti-capture-platforms.md`. **Последствия:** честная коммуникация заказчику — не «100% запрет».

## D-014: Foundation overkill (закон проекта)
**Решение:** E0 строим по-максимуму с дня 1 (полный audit-log, шифрование, серьёзный RBAC, security-примитивы), не MVP-урезка. **Обоснование:** директива Otabek «На Foundation не бывает Overkill» — фундамент держит всё. **Последствия:** E0 — серьёзный объём, оправдан для B2G.

---

> Будущие решения добавлять как D-015, D-016, … со ссылкой на разведку/спек.
