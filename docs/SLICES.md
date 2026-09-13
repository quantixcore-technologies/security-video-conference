# Слайс-трекер — Security Video Conference

> Единый реестр всех вертикальных слайсов (DB→Schema→Context→Engine→UI→Tests).
> Статус: ✅ done · 🔵 in progress · ⬜ planned · 🔒 blocked (заказчик/лицензия/R&D).
> Обновлять при закрытии каждого слайса. Источник истины по прогрессу проекта.

## 📊 Прогресс: **37 из 38 нумерованных слайсов готовы** (S1–S38; в работе только S34 — iOS 🔵)
> Сверх них: 7 ⬜ запланированных и 5 🔒 заблокированных пунктов без S-номера
> (номер присваивается при взятии в работу). Плюс безномерной Android-PoC ✅.
> Разбивка по эпикам — в заголовках таблиц ниже.

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

## E5 — Анти-захват ✅ 4/6
| # | Слайс | Статус |
|---|-------|--------|
| S15 | **E5-A** Watermark + журнал capture_events + матрица | ✅ |
| S16 | **E5-B** Журнал захвата UI (SecurityLive) + API endpoint | ✅ |
| S30 | **E5-C** Пер-встречная политика: `watermark_enabled` + `capture_reaction` (none/warn/eject) · `AntiCapture.enforce_policy` (warn→уведомление+audit · eject→LiveKit RemoveParticipant+audit) · gating watermark в звонке · UI в редакторе встречи | ✅ 2026-09-01 |
| S36 | **E5-DETECT** (D-018) Rust-детектор рекордеров в Tauri (`recorder.rs`) — сканер процессов (`sysinfo`), 35 сигнатур (OBS/Bandicam/Camtasia/ShareX/Snagit/XSplit… + remote-access AnyDesk/RustDesk/TeamViewer отдельной категорией) · фоновый watcher (5 с, дедуп по (имя,pid)) + команды `detect_recorders`/`client_platform` · пере-скан при входе в звонок · frontend шлёт `recorder_detected` → `/api/capture-events` и применяет `reaction` (warn→баннер · eject→выход из комнаты) | ✅ 2026-09-11 · 7 Rust-тестов (вкл. запуск реального процесса) + 5 контрактных тестов API |
| —   | **E5-ENFORCE** setContentProtected (Win) / FLAG_SECURE (Android) | ⬜ Android FLAG_SECURE ✅ · Tauri `contentProtected:true` задан → нужна Windows-валидация |
| —   | E5-forensic аудио-watermark | 🔒 R&D + библиотека |

## E7 — Сеть + Гео ✅ 3/5
| # | Слайс | Статус |
|---|-------|--------|
| S17 | **E7-A** Pre-join gate + Svc.Geo + журнал network_geo_checks | ✅ |
| S18 | **E7-B** Гео-политика per-org (mode/страны/whitelist/VPN) | ✅ |
| —   | **E7-C** locus/MaxMind интеграция (реальный country+VPN-детект) | 🔒 MMDB-лицензия |
| —   | E7-GPS кросс-чек | ⬜ требует mobile-клиент |
| S32 | **E7-spoofing** детект подмены геолокации (impossible-travel по GPS-истории, haversine, порог 900 км/ч) · поля spoofing/spoofing_reason · интеграция в gate (allow→flag) · метрика + бейдж в SecurityLive | ✅ 2026-09-01 (без MMDB — по GPS-истории пользователя) |

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
| S36 | Tauri — детектор рекордеров (Rust) → capture_events | ✅ 2026-09-11 — подробности в строке E5-DETECT выше |
| S23 | Android — **2FA(TOTP) через API** (login→totp_required→/api/login/totp→bearer) + экран ввода кода | ✅ собран, проверен на реальном устройстве (2026-06-08) |
| S24 | Android — **GPS-захват (E7) при join** — LocationManager → lat/lon/accuracy в join; backend gate пишет в network_geo_checks (+миграция gps_*) | ✅ собран, проверен на реальном устройстве (2026-06-08) |
| S25 | Android — **чат (LiveKit data, topic "chat") + screen-share (MediaProjection → LiveKit screencast)** | ✅ собран, установлен на устройство (2026-06-08) |
| S34 | iOS-клиент (SwiftUI): landing/login/2FA, встречи + создание, уведомления, отдел, профиль, Keychain, GPS, **isCaptured/screenshot detect → /api/capture-events** | 🔵 код написан (`mobile-ios/`), сборка — CI macOS runner; видео (LiveKit) — 2-й этап |
| S35 | **Обязательное OTA-обновление (D-017)** — `version.json`: `minVersionCode` + `ios.minBuild` · Android `UpdateManager` (mandatory, проверка права `REQUEST_INSTALL_PACKAGES`, скачивание + системный установщик, fail-open) · блокирующий `ForcedUpdateScreen` + `BackHandler {}` до логина · iOS `UpdateChecker` + `ForcedUpdateView` (блокировка + ссылка, установка — не разрешена Apple) | ✅ 2026-09-09 · проверено на эмуляторе end-to-end: блок → скачивание → установщик → v0.5.0 запустилось (без Chrome/Play Market) |
| S38 | **Авто-уведомление о новой версии (D-020)** — Oban Cron раз в 10 мин читает опубликованный `version.json`; новый Android `versionCode` → одна строка в `app_release_announcements` (unique `platform+version_code`, `on_conflict: :nothing`) + `:update` каждому активному пользователю в одной транзакции · доходит до установок v0.4.0+ через `NotifyWorker` даже при закрытом приложении и до старых сборок, не умеющих блокироваться · выключено без `APP_RELEASE_MANIFEST_URL` (в `runtime.exs` вне `:prod` — сервер в dev) | ✅ 2026-09-13 · 12 тестов · прод: путь cron (реальный fetch → разбор → дедуп) → `:already_announced`, 0.5.1 засеяна до рестарта |

## E8 — Встроенный помощник 🔵 1/2
| # | Слайс | Статус |
|---|-------|--------|
| S37 | **Помощник: бэкенд + веб** (D-019) — `Svc.Assistant` без LLM: база знаний 14 тем × uz/ru/en, поиск по ключевым словам с учётом морфологии (общий префикс ≥4, «хвост» ≤5) и отсевом стоп-слов · фильтр по ролям с честным `restricted` вместо тишины · REST `/api/assistant/{suggestions,ask,:id}` · плавающий виджет в лейауте админки (fetch к тому же API, что и мобильные) | ✅ 2026-09-13 · 20 тестов движка + 10 контрактных API + 3 на присутствие виджета |
| —   | **Помощник в Android и Tauri** — тот же API, нижняя панель в клиентах | ⬜ |

## Кросс-функциональные ⬜
| S28 | **Kod-sifat + xavfsizlik qatlami** — Credo (0 issue) · Sobelow (0 High/Med, CSP qo'shildi) · CI (GitHub Actions) · 0 compile-warning · 193 test | ✅ 2026-08-30 |

| S29 | **i18n foundation** — Gettext (uz/ru/en) · локаль-плаг + on_mount · переключатель языка · `/locale/:locale` · динамический `<html lang>` · навигация/сайдбар/шапка/auth переведены (uz/ru/en .po) | ✅ 2026-09-01 |
| S33 | **i18n полное покрытие** — весь UI обёрнут в `gettext()` (13 LiveView/контроллер-шаблонов + 3 контроллера: flash/ошибки логина/2FA) · default-домен 334 msgid (uz+en 0 пустых, ru=источник) · errors-домен 24 msgid (uz/ru переведены, en=источник) · runtime-проверка uz/ru/en OK | ✅ 2026-09-01 · 224 теста 0 failures, компиляция `--warnings-as-errors` чистая |
| S31 | **LiveKit Egress оркестрация** — `LiveKit.start_room_egress`/`stop_egress` (Twirp Egress API, best-effort) · `Recordings.auto_start` (system-запись по политике) + `pending_for_meeting`/`get_by_egress_id`/`stop_for_meeting` · webhook `egress_started`→mark_active, `egress_ended`→mark_completed, room_started→auto_start, room_finished→stop | ✅ 2026-09-01 (⚠️ реальный захват видео требует Egress-сервиса + storage-конфига в deploy) |

> **Не планируется:** OneID/E-IMZO интеграция (гос-SSO) — исключено из роадмапа (решение 2026-06-05). Внутренние учётки + 2FA достаточно.

---

## Легенда блокеров (🔒 — открытые вопросы заказчику)
- **Каналы уведомлений** (E3): email/SMS/Telegram санкционированы? Провайдер?
- **MaxMind-лицензия** (E7): закупка GeoIP2 Country + Anonymous IP баз.
- **Парк Windows** (E5/Tauri): билды для надёжности `setContentProtected`.
- **CRM-смысл** (E4): обращения граждан / поручения / задачи?
- **Forensic-аудио / deepfake** (E5/E6): R&D-бюджет, выбор библиотек.

> Подробности эпиков — `docs/superpowers/specs/E0..E7-*.md`. Текущее состояние — `CURRENT_STATUS.md`.
