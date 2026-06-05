# E5 — Анти-захват

> **Статус:** план-спек (далёкая фаза; детализируется перед Фазой 6). Greenfield.
> **Источники:** [research/anti-capture-platforms.md](../../research/anti-capture-platforms.md), ADR [D-013](../../ARCHITECTURE_DECISIONS.md) (слоистая стратегия), [D-001](../../ARCHITECTURE_DECISIONS.md) (web вне видео), [D-002](../../ARCHITECTURE_DECISIONS.md) (Tauri), мастер-план §4 (E5).

---

## ⚠️ Честная рамка (НЕ продавать как «100% запрет»)

> Из разведки ([anti-capture-platforms.md](../../research/anti-capture-platforms.md)) и [D-013]: **enforce возможен НЕ везде.**
> - **Скриншот/запись экрана:** ENFORCE на **Win** (`setContentProtected`→`WDA_EXCLUDEFROMCAPTURE`) + **Android** (`FLAG_SECURE`); **DETECT** на macOS/iOS; **IMPOSSIBLE** в web.
> - **Звукозапись:** **IMPOSSIBLE запретить нигде** (loopback/физ.микрофон/rooted) → только **forensic аудио-watermark** + трассировка.
> - **WDA_EXCLUDEFROMCAPTURE нестабилен** на части Win11-билдов (19045 — чёрный прямоугольник вместо контента).
>
> **Перевод ТЗ:** сдвиг с «prevent» на **«enforce-где-можно + detect + identify + deter + prosecute»**. Артефакт: [`docs/security/anti-capture-matrix.md`](../../security/anti-capture-matrix.md).

---

## Цель

Максимально затруднить и/или трассировать несанкционированный захват контента конференции: скриншот, запись экрана, звукозапись. Закрывает пункт ТЗ «запрещено скриншот / звукозапись / запись экрана» — честно, по слоистой стратегии.

---

## Scope (пункты ТЗ → задачи)

- **Enforce скриншот/запись (Win):** `setContentProtected(true)` в Tauri (baseline уже закладывается в E1) — проверка покрытия билдов, fallback-поведение.
- **Enforce (Android, mobile-фаза):** `FLAG_SECURE` на окне конференции.
- **Детект рекордеров (desktop):** Rust-сканер активных процессов записи (OBS, Bandicam и т.п.) → блок/предупреждение/лог.
- **Видимый per-user watermark:** overlay имя/ID/timestamp/SessionID поверх видео, низкая прозрачность — психологический детеррент + трассировка скриншота.
- **Forensic аудио-watermark:** неслышимый per-user идентификатор (User/Session/Timestamp), переживает ре-кодирование → трассировка утечки звука.
- **Детект (macOS/iOS, mobile/cross-фаза):** macOS-индикатор записи, iOS `UIScreen.isCaptured`/`userDidTakeScreenshot` — лог + реакция.
- **Kiosk/TPM-attestation (опц., high-security):** доверенная среда клиента (kiosk-режим, TPM-аттестация целостности).
- **Политика + юр.уведомление:** «запись запрещена, всё watermarked, нарушители идентифицируются».

---

## Ключевые задачи

1. **`setContentProtected` валидация (Win):** покрытие Win10 2004+/Win11-билдов; матрица протестированных билдов; поведение при сбое (19045) — деградация в детект+watermark. Tauri issue [#14200] — отслеживать.
2. **Rust-детектор рекордеров** (в Tauri shell): перечисление процессов (`CreateToolhelp32Snapshot` на Win), сигнатуры известных рекордеров, периодический скан → событие в Phoenix (audit) + клиентская реакция (warn/blur/eject по политике).
3. **Видимый watermark overlay:** рендер поверх LiveKit-видео (CSS/canvas-слой в WebView), per-user данные, движение/тайлинг против кропа, не мешает UX.
4. **Forensic аудио-watermark:** встраивание неслышимого ID в исходящий/входящий аудиотракт (Spread Spectrum / echo modulation). **R&D-компонент** — выбор библиотеки (ProveAudio/AWT2/кастомный SSW) + детектор для извлечения ID из утёкшей записи. См. риски.
5. **Детект на mac/iOS:** индикатор записи (macOS Sequoia 15+ оранжевый), iOS `isCaptured`/`capturedDidChange`, `userDidTakeScreenshotNotification` → лог + опц. pause/blur.
6. **Android `FLAG_SECURE` + callback** (mobile-фаза): блок скриншота + `addScreenRecordingCallback` детект + initial-state check; risk-scoring rooted.
7. **Anti-capture matrix-документ:** заполнить [`docs/security/anti-capture-matrix.md`](../../security/anti-capture-matrix.md) — enforce/detect/impossible per platform (из research).
8. **Политика/UX:** баннер-уведомление при входе, лог попыток захвата в `audit_logs`, opt-in policy per-meeting.
9. **Мониторинг:** session-логи, anomaly-детект, risk-scoring root/jailbreak.

---

## Технический подход

- **Enforce (Win):** **Tauri** ([D-002]) `setContentProtected` → нативный `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` на DWM-уровне; блокирует BitBlt/DXGI/Windows Graphics Capture/OBS. Гэпы (из research): нестабильность Win11-билдов, NDI/RTMP на сетевом уровне не остановить.
- **Детект рекордеров:** Rust в Tauri-shell — process enumeration + сигнатуры; событие → Phoenix через IPC/WS → `audit_logs`; реакция по policy.
- **Видимый watermark:** overlay-слой в WebView (поверх LiveKit JS видео); данные per-user из сессии.
- **Forensic аудио:** Spread Spectrum / echo modulation — неслышимо, переживает ре-кодирование; **детеррент ~40% снижение утечек** (research). Встраивание — на клиенте (Rust/WebAudio) или server-side при Egress (E6-инфра). **R&D-трек:** PoC + детектор обязательны до продакшена.
- **macOS/iOS/Android:** платформенные API (детект на mac/iOS, enforce на Android) — реализуются в mobile-фазе ([D-001] desktop-Win first).
- **Kiosk/TPM:** Rust-слой Tauri — опц., для high-security развёртываний; уточнить требование заказчика.
- **Фундаментально недостижимо (управлять ожиданиями, из research):** физическая вторая камера, rooted/jailbroken, аудио-loopback, web-скриншот OS-средствами, macOS ScreenCaptureKit, браузер-расширения. **Web исключён из видео** ([D-001]) — снимает самый дырявый вектор.

---

## Предварительные доменные сущности (Ecto)

> Большая часть E5 — **клиентский (Tauri/Rust) + платформенный** код; БД хранит политику, события и watermark-привязки. Все таблицы несут `org_id` ([D-005]).

- **capture_events** `(id, org_id, meeting_id, user_id, kind [screenshot_detected|recorder_detected|screen_record_detected|protection_failed], platform, detail jsonb, severity, occurred_at, client_session_id)` — журнал попыток/детектов захвата.
- **watermark_assignments** `(id, org_id, meeting_id, user_id, session_id, visible_payload, audio_token, issued_at)` — привязка watermark-ID к (пользователь, сессия) для последующей трассировки утечки.
- **anti_capture_policies** `(id, org_id, meeting_id?, enforce_screen_capture bool, detect_recorders bool, visible_watermark bool, audio_watermark bool, on_violation [warn|blur|eject], require_kiosk bool)` — политика per-org/per-meeting (или в `meetings`/`organizations.settings` jsonb).
- *(опц.)* **client_attestations** `(id, org_id, user_id, session_id, tpm_quote, kiosk bool, root_jailbreak_risk, verified_at)` — TPM/kiosk-аттестация.

---

## Риски

- **enforce только Win/Android** (из research/[D-013]): macOS `NSWindowSharingNone`/ScreenCaptureKit **не блокируется** (Apple намеренно), iOS скриншот **не заблокировать** — только детект. Честная коммуникация заказчику.
- **WDA нестабилен на Win11-билдах** (#47834-класс проблема, 19045 — чёрный прямоугольник) → нужна матрица билдов парка заказчика (открытый вопрос мастер-плана) + graceful degradation.
- **Звук — невозможно запретить нигде** → только forensic watermark; эффект — детеррент (~40%), не гарантия.
- **Forensic аудио-watermark = R&D:** робастность к ре-кодированию/обрезке, ложные срабатывания детектора, библиотека незрелая (кастомный SSW рискован) — бюджет на PoC + валидацию.
- **Tauri `setContentProtected` зрелость** ([D-002] последствие — PoC обязателен; issue #14200) — подтвердить поведение на целевых билдах в E1-спайке.
- **Физические/rooted-векторы недостижимы** — вторая камера, jailbreak, loopback. Управлять ожиданиями.

---

## Зависимости

- **E1** (Ядро конференций) — Tauri-клиент + `setContentProtected` baseline + LiveKit-видео (поверх него watermark).
- **E0** (Фундамент) — `audit_logs` для `capture_events`, users/sessions для watermark-привязки.
- *(инфра-связь)* **E6** — server-side Egress может нести аудио-watermark embed; общий ML/media-silo.
- **mobile-клиент** (фаза 2) — Android `FLAG_SECURE`, iOS-детект.

---

## Открытые вопросы

1. **Парк Windows-билдов заказчика** (из мастер-плана §14): какие Win10/11-билды? Надёжность `setContentProtection` на них — критично для enforce.
2. **Реакция на детект:** warn / blur / eject из встречи / только лог? Политика per-meeting или глобальная?
3. **Forensic аудио-watermark:** требуется ли реально (R&D-стоимость велика), или достаточно видимого watermark + политики? Какая библиотека/подход санкционированы?
4. **Kiosk/TPM:** требуется ли доверенная среда (managed-устройства), или клиенты на личных машинах?
5. **macOS/iOS в контуре:** есть ли пользователи на Apple, или парк только Win+Android (упрощает — убирает detect-only платформы)?
6. **Юр.основание:** формулировка политики/уведомления о запрете записи (гос-юрист) — для prosecute-слоя.
7. **Embed аудио-watermark:** на клиенте (per-user исходящий) или server-side (Egress, единый)? Влияет на архитектуру и latency.
