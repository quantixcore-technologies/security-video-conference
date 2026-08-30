# Current Status — Security Video Conference

> Снимок состояния для следующей сессии / после /compact. Обновлять в конце сессии.

## Срез 1 ГОТОВ + редизайн + профиль ✅ (работает вживую)

### Сессия 2026-06-05 (S1) — с нуля до живого продукта с enterprise-UI
- ✅ **E0** Фундамент: Orgs(иерархия), Accounts(Argon2+TOTP+lockout), Authz(RBAC scoping), Audit(append-only), LiveView-админка.
- ✅ **E1** Ядро: LiveKit self-host(docker), Svc.LiveKit(JWT), Meetings, webhook(HMAC), join-API, **живой видеозвонок** (dev: `/admin/meetings/:id/call`).
- ✅ **E2** Посещаемость: ростер, attendance(статусы), Oban FinalizeWorker, Recordings(Egress-сущность), журнал-UI.
- ✅ **Редизайн «Secure Operations»**: тёмная slate+emerald, IBM Plex, sidebar+heroicons, все 8 страниц переделаны (login/totp/dashboard/users/meetings/show/call), фото-upload, totp Cloak-шифрование, **профиль в sidebar везде** + профиль-карточка на dashboard, карточки участников звонка (аватары).
- ✅ **31 коммит · 104 теста 0 failures**, запушено в приватный репозиторий.
- ✅ Доказано вживую: login→dashboard→встречи→журнал; реальный звонок 2 участника→webhook→авто-посещаемость.

## ✅ Сделано после редизайна (62 коммита, 181 тест 0 failures)
- Расширенные контролы звонка (screen-share, участники+говорящий, чат, mute, fullscreen, устройства).
- Профиль-рефактор: top-right avatar dropdown + `/admin/profile` (дублирование убрано).
- **UX-аудит P0+P1+P2 закрыт** (`docs/UX-AUDIT.md`): управление сотрудниками/встречами + карточка `users/:id`, 2FA enrollment (QR/eqrcode), mobile-бургер, emerald loading-bar, повтор пароля, поиск/фильтр/пагинация таблиц, локализация статусов/действий, a11y (alt).
- **Эпик E3 (A–F)** — планирование: уведомления+колокольчик · напоминания (Oban T-24ч/1ч) · календарь (месяц) · RSVP · recurring-встречи · `.ics`-экспорт. _(внешние каналы email/SMS/Telegram — blocked заказчиком)._
- **E5 анти-захват (A+B):** per-user watermark на звонке · юр-баннер · `capture_events` журнал + API `/api/capture-events` · `SecurityLive` (`/admin/security`) · матрица. _(ENFORCE setContentProtected/FLAG_SECURE — Tauri/mobile-фаза)._
- **E7 сеть/гео (A+B):** pre-join gate + `Svc.Geo` (classify_ip RFC1918, журнал) · **гео-политика per-org** (`geo_policies`: mode off/flag_only/enforce, allowed_countries, whitelist_ips, block_vpn/proxy) · полная security-панель `/admin/security` (политика + журнал захвата + журнал гео). _(реальный VPN/country = MaxMind MMDB через locus, открытый вопрос лицензии)._

- **E4 поручения/задачи (A+B+C):** backend `tasks` (creator→assignee, meeting_id, priority, status todo/in_progress/review/done, due_at) · `Svc.Tasks` (create/set_status/board/open_count/can_manage?) · ADR **D-015** («CRM» для гос = поручения+задачи, НЕ sales-CRM) · **Kanban-доска** `/admin/tasks` (4 колонки, карточки приоритет/исполнитель/срок, HTML5 drag-drop, RBAC) · **E4-C** поручение из совещания (кнопка «Поручение» на встрече → `/meetings/:id/assign-task`, meeting-бейдж на карточке) + **in-app уведомление исполнителю** при назначении (kind `:task`, в контексте `create_task` — работает из доски И из встречи, кроме «сам себе») · **E4-D** отчётность (`Svc.Tasks.stats/overdue_count/summary_by_assignee` · виджет «Мои поручения» на дашборде с просрочкой · сводная панель + таблица «по исполнителям» для руководителя). **ЭПИК E4 ЗАКРЫТ (4/4).** _(обращения граждан 🔒 заказчик)._

## 📱 Сессия 2026-06-07 — нативный Android-клиент (PoC) ✅ ДОКАЗАНО НА УСТРОЙСТВЕ
- **Стек:** Kotlin + Jetpack Compose + LiveKit Android SDK 2.18.2 (нативный WebRTC, НЕ webview — D-001). Папка `mobile/`.
- **Backend:** добавлен bearer-auth для нативных клиентов — `POST /api/login` → Phoenix.Token; plug `fetch_api_user` (API принимает session-cookie ИЛИ bearer). **48 тестов 0 failures** (+5 API-тестов).
- **Экраны:** `MainActivity` (вход: сервер/логин/пароль/ID) → `SvcApi` (login+join, подмена loopback-хоста на хост сервера) → `CallActivity` (LiveKit-комната, локальное+удалённое видео, mic/cam).
- **E5 enforce (Android):** `FLAG_SECURE` на `CallActivity` — анти-скриншот/запись работает (на эмуляторе screencap чёрный, window-флаг `SECURE` подтверждён).
- **✅ Проверено вживую на РЕАЛЬНОМ устройстве** (Realme RMX3636, Android 14, arm64) через USB + `adb reverse tcp:4000/7880`: вход → bearer → join → LiveKit → видео с реальной камеры. (Ранее также на эмуляторе android-35.) APK `mobile/app/build/outputs/apk/debug/app-debug.apk` (59MB).
- ⚠️ Локальный стек **нативный, без Docker:** PostgreSQL :5432, LiveKit binary :7880 (`/home/darkside/livekit.native.yaml`), Redis :6379. Эмулятор: хост = `10.0.2.2`; реальное устройство по USB: `adb reverse` → `127.0.0.1`.
- **✅ 2FA(TOTP) через API (2026-06-08, S23):** `/api/login` при `totp_enabled` отдаёт `{totp_required, totp_token}` (промежуточный токен 5 мин, `UserAuth.sign_totp_token`); новый `POST /api/login/totp` меняет код+токен на bearer. Мобайл: sealed `LoginResult` (Success/TotpRequired) + экран ввода 6-значного кода. **53 теста 0 failures** (+5 API-тестов 2FA). APK пересобран.
- **✅ GPS-захват (E7) при join (2026-06-08, S24):** мобайл `currentGeo()` (LocationManager, без Play Services) → `lat/lon/accuracy` в `POST /api/meetings/:id/join`. Backend: `MeetingController.join` зовёт `Svc.Geo.gate` (IP-классификация + запись GPS в `network_geo_checks`, миграция `gps_lat/lon/accuracy`). MVP без MMDB: только :allow/:flag (никогда :block); :block-ветка появится с MaxMind (D-012, fail-closed by компилятор). **55 тестов 0 failures** (+2 gate-теста).
- **✅ Чат + screen-share (2026-06-08, S25):** чат через LiveKit data-сообщения (topic "chat", reliable; `RoomEvent.DataReceived`) + панель чата в `CallActivity`. Screen-share через MediaProjection → `setScreenShareEnabled(true, ScreenCaptureParams(intent))`; foreground-сервис предоставляет SDK (`ScreenCaptureService` в манифесте, +FOREGROUND_SERVICE_MEDIA_PROJECTION). ⚠️ FLAG_SECURE: окно звонка в захвате будет чёрным (демонстрируют сторонний контент). APK установлен на RMX3636.
- **✅ LIVE-проверка на устройстве (2026-06-08, RMX3636 Android 14, через adb + нативный стек):** логин→join→LiveKit: реальная камера (VP8 1280×720) + микрофон опубликованы (подтверждено логами LiveKit/webhook). **GPS** реальные координаты телефона записаны в `network_geo_checks` (41.56/60.61, ±16м). **FLAG_SECURE** подтверждён (screencap = чёрный/0 байт). **2FA**: экран TOTP появляется при `totp_required`, неверный код→401, верный код→bearer→вход в звонок (полный цикл пройден на устройстве). totp_token=5мин, code=30с — учитывать при ручном тесте.
- **TODO Android:** live-тест чата/screen-share на 2 устройствах (нужен 2-й участник). **iOS** — позже на macOS (Swift).

## 🖥️ Сессия 2026-08-28 — Tauri desktop-клиент (E1) ✅

- **Стек:** Tauri v2 (Rust 1.98 + webkit2gtk-4.1 + Vite/vanilla-TS), tauri-cli 2.11, bun 1.4. Папка `desktop/` (identifier `uz.svc.desktop`).
- **S26 — каркас:** экран входа SVC (сервер/username/пароль/ID встречи → 2FA-поток), тёмная teal-тема (как web), `contentProtected:true` (Win/macOS enforce, Linux no-op — D-013), Rust-команда `security_status`. Окно рендерится (xvfb).
- **S27 — LiveKit-звонок:** login(username)→`/api/login`→bearer→`/api/meetings/:id/join`→комната; локальное+удалённое видео, mic/cam toggle, «Chiqish», per-user watermark(E5). **native HTTP** (`tauri-plugin-http`) вместо webview-fetch — обход CORS.
- **✅ Проверено (xvfb, admin/AdminPass12345, meeting 1):** login→join→**issue_token** (backend-лог: fetch_meeting + geo-gate `:allow` + audit `meeting_join` + LiveKit JWT). Экран звонка (комната, контролы, watermark) рендерится. Видео-медиа не поднялось в headless webkit (нет камеры/WebRTC) → работает на реальном десктопе / Windows (WebView2, D-002).
- **Коммиты:** `feat(desktop): Tauri-каркас (E1)` + `feat(desktop): LiveKit видеозвонок + native HTTP (E1)`. Автор: QuantixCore.
- **🧹 Очистка проекта:** из файлов, коммит-сообщений и авторства удалены упоминания прежнего участника + внешнего git-хоста/оргструктуры (история переписана, remote и токен убраны). В доках команда: Furqat / Shuxrat. Android-пакет → `uz.svc`.

## 🛡 Сессия 2026-08-30 — качество + безопасность (S28) ✅
- **Credo** (кастомный `.credo.exs`) → **0 issues** · **Sobelow** security-скан → **0 High/Medium** (CSP-заголовок в browser-pipeline; CSRF на bearer-API — задокументированный false-positive; photo upload — whitelist расширений).
- **CI** (`.github/workflows/ci.yml`): compile(warnings-as-errors)/format/credo/sobelow/test. `mix precommit` расширен теми же гейтами.
- Компиляция **без warnings**; **193 теста, 0 failures**. Коммит `3b3f891`.

## ⏭️ СЛЕДУЮЩИЙ КВЕСТ (Tauri-каркас + звонок готовы ✅ S26/S27)
- 🔴 **Tauri видео на Windows** — проверить реальное WebRTC-медиа в WebView2 + `setContentProtected` enforce (Linux webkit2gtk WebRTC ненадёжен; D-002 Windows-first).
- **2-сторонний тест** — desktop ↔ web-call (`/admin/meetings/1/call`) / mobile: встречное видео.
- **Tauri — детектор рекордеров (Rust)** → capture_events (E5).
- **E5-C** политика захвата per-meeting · **E6-A** ML-инфра (🔒 GPU/R&D) · **i18n** RU/UZ/EN.
> Открытые вопросы заказчику собраны в `docs/requirements-interview.md` (6 блоков) — разблокируют E4-обращения, E3-каналы, E5-enforce, E7-MMDB, E6-ML, комплаенс.
> ❌ OneID/E-IMZO — НЕ планируется (D-006, 2026-06-05).

## ⚠️ Локальный запуск (КРИТИЧНО) — НАТИВНЫЙ стек (Docker daemon выключен → native, порт 5432)
```bash
redis-server --daemonize yes --port 6379                    # Redis (нужен LiveKit)
livekit-server --config ~/livekit.native.yaml               # LiveKit :7880 (ключи devkey/devsecret)
mix phx.server                                              # :4000 (DB_PORT по умолч. 5432), admin/AdminPass12345
mix test                                                    # тесты
mix run apps/svc/priv/repo/seeds.exs                        # демо-данные (6 юзеров)
cd desktop && bun run tauri dev                            # Tauri desktop-клиент
# Docker-вариант (если поднять daemon): deploy/livekit/docker-compose.yml + DB_PORT=5434
```
**Oban v14. Cloak dev-key в config.exs, prod из env CLOAK_KEY.**
**Тесты после redesign проверяют href (`/admin/users/new`), не текст кнопок.**

## 📋 Backlog (docs/BACKLOG.md) · слайс-трекер (docs/SLICES.md)
i18n RU/UZ/EN · Tauri-клиент · реальный LiveKit Egress · E4/E6 · остатки E5/E7.
> ❌ OneID/E-IMZO — НЕ планируется (решение 2026-06-05).

## ❓ Открытые вопросы заказчику
Комплаенс O'zDSt/СКЗИ · парк Windows · каналы уведомлений E3 · смысл «CRM»(E4) · mobile-стек · хранение записей.

## 📚 Ключевые доки
ADR: `docs/ARCHITECTURE_DECISIONS.md` (14) · разведка: `docs/research/` (4) · спеки: `docs/superpowers/specs/E0-E7` · итоги: `docs/sessions/2026-06-05.md` · `CLAUDE.md`(навигация).
