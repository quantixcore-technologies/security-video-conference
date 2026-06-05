# Anti-Capture Matrix — Security Video Conference (E5)

> Основания: **D-001** (видео — нативный клиент, web только управление), **D-013** (anti-capture — слоистая стратегия).
> Разведка: [research/anti-capture-platforms.md](../research/anti-capture-platforms.md).
> Связано: [SECURITY.md](SECURITY.md) §3.6 (актор B — недобросовестный сотрудник).
> Требование ТЗ: «запрещено скриншот / звукозапись / запись экрана».

---

## 1. Главный вывод (честно заказчику)

**Enforce возможен НЕ везде.** Поэтому стратегия — не «запретить всё», а
**«enforce-где-можно + детект + watermark + трассировка + политика»**. Сдвиг парадигмы:

> **prevent → detect, identify, prosecute.**

Ключевое архитектурное следствие (**D-001**): web — самая дырявая платформа (скриншот OS-средствами
не блокируется и не детектится надёжно) → **видео вынесено из web полностью**; web несёт только
управление (админка/журналы/планирование). Видеоконференция — **только нативный клиент (Tauri)**.

---

## 2. Полная матрица возможностей

Состояния: **ENFORCE** (реально блокируем) · **DETECT** (не блокируем, но обнаруживаем/логируем) ·
**IMPOSSIBLE** (не блокируем и не детектируем надёжно).

| Угроза \ Платформа | Web | Electron/Tauri-Win | Electron/Tauri-mac | Android | iOS |
|--------------------|-----|--------------------|--------------------|---------|-----|
| **Скриншот** | ❌ IMPOSSIBLE | ✅ ENFORCE — `setContentProtected(true)` → `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` ⚠️ | ⚠️ DETECT — `NSWindowSharingNone` сломан ScreenCaptureKit; оранжевый индикатор menu bar (Sequoia 15+) | ✅ ENFORCE — `FLAG_SECURE` (WindowManager.LayoutParams) | ⚠️ DETECT — `userDidTakeScreenshotNotification` (post-facto); трюк `UITextField(isSecureTextEntry:true)` рендерит чёрное (косметика) |
| **Запись экрана** | ❌ IMPOSSIBLE | ✅ ENFORCE* — тот же `WDA_EXCLUDEFROMCAPTURE` (блок BitBlt/DXGI/Windows Graphics Capture/OBS) | ⚠️ DETECT — macOS 15 ScreenCaptureKit обходит `NSWindowSharingNone`; оранжевый индикатор | ⚠️ DETECT — `MediaProjection` callback + initial-state check; `FLAG_SECURE` → чёрное для non-secure virtual displays | ⚠️ DETECT — `UIScreen.isCaptured` + `capturedDidChange` (запись/AirPlay/mirroring) |
| **Звукозапись** | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE |

\* **`WDA_EXCLUDEFROMCAPTURE`:** работает Win10 2004+, но **нестабилен на части Win11-билдов**
(билд 19045 показывает чёрный прямоугольник; Electron #47834). Tauri: `setContentProtected` →
тот же Win32-механизм на DWM-уровне. **Гэп:** NDI/RTMP-стриминг на сетевом уровне не останавливается.

### Уточнения по платформам (из разведки)
- **Win (enforce):** блокирует BitBlt / DXGI / Windows Graphics Capture / OBS на DWM-уровне.
  Гэпы: нестабильность Win11-билдов (#47834), сетевой NDI/RTMP не перехватить.
- **macOS (detect-only):** `NSWindowSharingNone` **полностью неэффективен** против ScreenCaptureKit
  (macOS 15+, Apple намеренно изменил compositing — Zoom/OBS обходят). Остаётся оранжевый индикатор
  в menu bar (Sequoia 15+) как видимый сигнал.
- **Android (enforce):** `FLAG_SECURE` блокирует скриншоты, recent-apps preview, non-secure virtual
  displays (MediaProjection → чёрное). Flutter-аналог: `flutter_windowmanager`. Гэпы: rooted-устройства,
  физическая вторая камера, CVE-2025-32322 (MediaProjection bypass). Детект записи: `addScreenRecordingCallback`.
- **iOS (detect-only):** скриншот **заблокировать нельзя**. Детект пост-фактум
  (`userDidTakeScreenshotNotification`) и записи/зеркалирования (`UIScreen.isCaptured`).
- **Web (impossible):** `getDisplayMedia`/скриншот **нельзя ни блокировать, ни надёжно детектить**.
  Слабые митигации (`visibilitychange`→pause+blur ~20-30%, обходится расширением; canvas-watermark;
  EME/Widevine L1 только Win+Chrome ~70-80%, сложно, латентность) → **web исключён из видео-контура (D-001).**

---

## 3. Звукозапись — невозможно запретить нигде

Loopback-аудио, физический микрофон рядом, rooted-устройство — звук перехватывается на любой
платформе, OS-средствами это не блокируется. **Единственная рабочая митигация:**

**Forensic AUDIO WATERMARKING** — неслышимый per-user идентификатор (User / Session / Timestamp),
встраиваемый в аудиопоток (Spread Spectrum / echo modulation), **переживает ре-кодирование**.
Утечку записи трассируют до конкретного пользователя. Эффект — детеррент (~40% снижение утечек по
данным разведки). Библиотеки/подходы: ProveAudio, ScoreDetect, AWT2, Tencent Cloud, кастомный SSW.

---

## 4. Слоистая стратегия (6 слоёв, D-013)

| # | Слой | Что делает | Где |
|---|------|-----------|-----|
| 1 | **ENFORCE** | Реальная блокировка захвата | Win `setContentProtected` (Tauri), Android `FLAG_SECURE`, iOS secure-field трюк (косметика) |
| 2 | **DETECT & DETER** | Обнаружение + лог попыток | macOS оранжевый индикатор, Android `addScreenRecordingCallback`, iOS `UIScreen.isCaptured`, (web `visibilitychange` — для не-видео) |
| 3 | **Видимый per-user watermark** | Психологический детеррент | overlay: **ФИО + SessionID + timestamp**, низкая прозрачность, поверх видео |
| 4 | **Forensic аудио-watermark** | Трассировка утечки до пользователя | неслышимый per-user ID в аудио (см. §3) |
| 5 | **Политика + юр.уведомление** | Правовой детеррент | «запись запрещена; всё watermarked; нарушители идентифицируются» — при входе в встречу |
| 6 | **Мониторинг** | Поведенческий контроль | session-логи, anomaly-детект, risk-scoring root/jailbreak (привязка к audit) |

**Логика:** слой 1 закрывает Win/Android; слой 2 даёт видимость там, где enforce невозможен (mac/iOS);
слои 3-4 покрывают то, что технически не блокируется (вторая камера, звук) — через идентификацию и
трассировку; слои 5-6 — организационный и поведенческий контур. Каждая попытка/детект → в audit-log
([SECURITY.md](SECURITY.md) §3.3).

---

## 5. Фундаментально недостижимо (управление ожиданиями заказчика)

> **Это нужно проговорить с заказчиком ДО внедрения.** Ниже — то, что не блокирует ни одна платформа
> и ни одна технология. Обещать «100% запрет» здесь = ввести заказчика в заблуждение (нарушение D-013).

- **Физическая вторая камера / телефон** снимает экран — не детектируется и не блокируется ничем.
- **Звукозапись** (микрофон рядом, аудио-loopback) — не блокируется **нигде** (только watermark+трассировка).
- **Web-скриншот** OS-средствами — нельзя блокировать/надёжно детектить → web без видео (D-001).
- **macOS ScreenCaptureKit** (15+) обходит content-protection — на mac только детект.
- **iOS-скриншот** — блокировать нельзя, только пост-фактум детект.
- **Widevine L1** — работает только на Win+Chrome, не универсален, не применяется (web вне видео).
- **Браузер-расширения** отключают Page Visibility API — web-митигации обходятся.
- **Rooted / jailbroken** устройства снижают эффективность enforce (FLAG_SECURE/content-protection) →
  детект и risk-scoring, не гарантия.
- **Нестабильность Win11-билдов** (#47834) — на части билдов enforce даёт чёрный прямоугольник/сбой.

**Честный перевод ТЗ:**
- Скриншот/запись экрана — **блокируемо на Win + Android**, **детект на iOS / macOS**, **невозможно на web** (→ web вне видео).
- Звук — **нигде не блокируемо** → forensic-watermark + трассировка.
- Итог: **«detect, identify, prosecute»**, а не «полный технический запрет».

---

## 6. Привязка к ADR
- **D-001** — видео только нативный клиент; web (самая дырявая платформа) — без видео.
- **D-002** — Tauri как desktop-shell: `setContentProtected` → нативный Win32 enforce; Rust-shell для детекта/TPM/kiosk.
- **D-013** — слоистая стратегия + честная коммуникация заказчику (не «100% запрет»).
- Связь с **D-009** (серверная запись по политике — ортогональна «запрету записи участниками»:
  запись организацией ≠ захват участником) и **D-010** (анти-захват защищает контент на endpoint,
  шифрование защищает канал — разные контуры).

---

## 7. Статус реализации (web-слой E5, 2026-06-05)

Реализовано в web call-page (слои трассировки — работают без Tauri):
- ✅ **Видимый per-user watermark** (слой 3): диагональный tiled SVG-overlay с
  **ФИО + ID пользователя + время**, поверх видео (`call_html/show.html.heex`).
- ✅ **Журнал `capture_events`** (слой 6): таблица + `Svc.AntiCapture` контекст
  (`log_event`/`list_events`/`critical_count`) — для детектов от нативного клиента.
- ✅ **Юр. баннер** (слой 5): «Запись запрещена · контент watermarked» в звонке.

Отложено (требует Tauri / mobile / R&D):
- ⏳ **ENFORCE** (слой 1): `setContentProtected` (Win) / `FLAG_SECURE` (Android) — Tauri-клиент.
- ⏳ **DETECT** (слой 2): Rust-сканер рекордеров, macOS/iOS-индикаторы → шлют в `capture_events`.
- ⏳ **Forensic аудио-watermark** (слой 4): R&D.
