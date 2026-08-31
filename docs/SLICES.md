# Слайс-трекер — Security Video Conference

> Единый реестр всех вертикальных слайсов (DB→Schema→Context→Engine→UI→Tests).
> Статус: ✅ done · 🔵 in progress · ⬜ planned · 🔒 blocked (заказчик/лицензия/R&D).
> Обновлять при закрытии каждого слайса. Источник истины по прогрессу проекта.

## 📊 Прогресс: 30 ✅ · 11 ⬜ · 5 🔒 — **30 из ~40** (+ Android: PoC, 2FA, GPS, чат/screen-share · + Tauri desktop · + i18n)

---

## Срез 1 — Фундамент (Milestone 1) ✅ 3/3
| # | Слайс | Статус |
|---|-------|--------|
| S1 | **E0** Фундамент — orgs/accounts(Argon2+TOTP)/RBAC/audit/админка | ✅ |
| S2 | **E1** Ядро — LiveKit self-host, JWT, webhook(HMAC), живой звонок | ✅ |
| S3 | **E2** Посещаемость — ростер, статусы, Oban finalize, журнал-UI | ✅ |

## Редизайн + UX-аудит ✅ 5/5
| # | Слайс | Статус |
|---|-------|--------|
| S4 | Редизайн «Secure Operations» (тёмная slate+emerald, IBM Plex, 8 страниц) | ✅ |
| S5 | Расширенные контролы звонка + профиль-рефактор (top-right avatar) | ✅ |
| S6 | UX **P0** — управление сотрудниками/встречами + карточка users/:id + 2FA enrollment | ✅ |
| S7 | UX **P1** — mobile-бургер · emerald loading-bar · повтор пароля | ✅ |
| S8 | UX **P2** — поиск/фильтр/пагинация · локализация статусов/действий · a11y | ✅ |

## E3 — Планирование + Уведомления ✅ 6/6 (внешние каналы 🔒)
| # | Слайс | Статус |
|---|-------|--------|
| S9  | **E3-A** In-app уведомления + колокольчик | ✅ |
| S10 | **E3-B** Напоминания (Oban, T-24ч/1ч) | ✅ |
| S11 | **E3-C** Календарь встреч (месяц-вид) | ✅ |
| S12 | **E3-D** RSVP (Приду/Возможно/Не приду) | ✅ |
| S13 | **E3-E** Recurring-встречи (серии) | ✅ |
| S14 | **E3-F** `.ics`-экспорт (Outlook/Google) | ✅ |
| —   | E3-внешние каналы (email/SMS/Telegram) | 🔒 каналы для гос = открытый вопрос |

## E5 — Анти-захват ✅ 3/5
| # | Слайс | Статус |
|---|-------|--------|
| S15 | **E5-A** Watermark + журнал capture_events + матрица | ✅ |
| S16 | **E5-B** Журнал захвата UI (SecurityLive) + API endpoint | ✅ |
| S30 | **E5-C** Пер-встречная политика: `watermark_enabled` + `capture_reaction` (none/warn/eject) · `AntiCapture.enforce_policy` (warn→уведомление+audit · eject→LiveKit RemoveParticipant+audit) · gating watermark в звонке · UI в редакторе встречи | ✅ 2026-09-01 |
| —   | **E5-ENFORCE** setContentProtected (Win) / FLAG_SECURE (Android) | ⬜ Android FLAG_SECURE ✅ · Tauri `contentProtected:true` задан → нужна Windows-валидация |
| —   | E5-forensic аудио-watermark | 🔒 R&D + библиотека |

## E7 — Сеть + Гео ✅ 2/5
| # | Слайс | Статус |
|---|-------|--------|
| S17 | **E7-A** Pre-join gate + Svc.Geo + журнал network_geo_checks | ✅ |
| S18 | **E7-B** Гео-политика per-org (mode/страны/whitelist/VPN) | ✅ |
| —   | **E7-C** locus/MaxMind интеграция (реальный country+VPN-детект) | 🔒 MMDB-лицензия |
| —   | E7-GPS кросс-чек | ⬜ требует mobile-клиент |
| —   | E7-spoofing-детект (IP↔GPS mismatch) | ⬜ |

## E4 — Поручения + Задачи (Kanban) ✅ 4/4 — ЭПИК ЗАКРЫТ (D-015)
| # | Слайс | Статус |
|---|-------|--------|
| S19 | **E4-A** Tasks backend — поручение/задача (автор→исполнитель, дедлайн, приоритет, статус) | ✅ |
| S20 | **E4-B** Kanban-доска UI (4 колонки, карточки, HTML5 drag-drop, RBAC manage vs read-only) | ✅ |
| S21 | **E4-C** Поручение из совещания (кнопка на встрече, meeting-бейдж на карточке) + уведомление исполнителю | ✅ |
| S22 | **E4-D** Отчётность (stats/overdue/по исполнителям · виджет «Мои поручения» · сводка руководителя) | ✅ |
| —   | E4 Обращения граждан (отдельный модуль) | 🔒 уточнить у заказчика |

## E6 — ML liveness / deepfake ⬜ 0/4
| —   | **E6-A** ML-сервис инфра (Python+Rust, gRPC/REST) | ⬜ |
| —   | **E6-B** Face-match к фото (InsightFace, ~98%) | ⬜ |
| —   | **E6-C** Liveness (MiniFASNet + challenge) | ⬜ |
| —   | E6-D Deepfake-флаг (~78%, risk-flag не автобан) | 🔒 R&D |

## Клиенты (критический путь prod-видео)
| —   | **Android-клиент PoC** — Kotlin+Compose+LiveKit (нативный WebRTC), bearer-auth API, видеозвонок + **FLAG_SECURE** | ✅ собран и проверен на эмуляторе (2026-06-07) |
| S26 | **Tauri-каркас** — scaffold (Vite+TS / src-tauri, `uz.svc.desktop`), экран входа SVC (username → 2FA), `contentProtected:true`, Rust-команда `security_status` | ✅ собран+запущен под xvfb (2026-08-28) |
| S27 | **Tauri LiveKit-звонок** — login(username)→join→комната, локальное+удалённое видео, mic/cam, per-user watermark(E5), native HTTP (tauri-plugin-http, обход CORS) | ✅ login→join→issue_token подтверждён backend-логом; видео-медиа = Windows/WebRTC-webview (2026-08-28) |
| —   | Tauri — `setContentProtected` enforce (Windows-валидация) | ⬜ |
| —   | Tauri — детектор рекордеров (Rust) → capture_events | ⬜ |
| S23 | Android — **2FA(TOTP) через API** (login→totp_required→/api/login/totp→bearer) + экран ввода кода | ✅ собран, проверен на реальном устройстве (2026-06-08) |
| S24 | Android — **GPS-захват (E7) при join** — LocationManager → lat/lon/accuracy в join; backend gate пишет в network_geo_checks (+миграция gps_*) | ✅ собран, проверен на реальном устройстве (2026-06-08) |
| S25 | Android — **чат (LiveKit data, topic "chat") + screen-share (MediaProjection → LiveKit screencast)** | ✅ собран, установлен на устройство (2026-06-08) |
| —   | iOS-клиент (Swift, isCaptured detect, GPS) | ⬜ требует macOS |

## Кросс-функциональные ⬜
| S28 | **Kod-sifat + xavfsizlik qatlami** — Credo (0 issue) · Sobelow (0 High/Med, CSP qo'shildi) · CI (GitHub Actions) · 0 compile-warning · 193 test | ✅ 2026-08-30 |

| S29 | **i18n foundation** — Gettext (uz/ru/en) · локаль-плаг + on_mount · переключатель языка · `/locale/:locale` · динамический `<html lang>` · навигация/сайдбар/шапка/auth переведены (uz/ru/en .po) | ✅ 2026-09-01 |
| —   | i18n — полное покрытие страниц (LiveView-контент: meetings/tasks/users/security/profile…) | ⬜ инфра готова (S29), осталось обернуть ~210 строк |
| —   | Реальный LiveKit Egress (серверная запись) | ⬜ сущность-заглушка есть |

> **Не планируется:** OneID/E-IMZO интеграция (гос-SSO) — исключено из роадмапа (решение 2026-06-05). Внутренние учётки + 2FA достаточно.

---

## Легенда блокеров (🔒 — открытые вопросы заказчику)
- **Каналы уведомлений** (E3): email/SMS/Telegram санкционированы? Провайдер?
- **MaxMind-лицензия** (E7): закупка GeoIP2 Country + Anonymous IP баз.
- **Парк Windows** (E5/Tauri): билды для надёжности `setContentProtected`.
- **CRM-смысл** (E4): обращения граждан / поручения / задачи?
- **Forensic-аудио / deepfake** (E5/E6): R&D-бюджет, выбор библиотек.

> Подробности эпиков — `docs/superpowers/specs/E0..E7-*.md`. Текущее состояние — `CURRENT_STATUS.md`.
