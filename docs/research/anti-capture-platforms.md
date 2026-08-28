# Разведка: Анти-захват по платформам (E5)

> Источник: research-отряд №2. Требование ТЗ: «запрещено скриншот / звукозапись / запись экрана».
> Главный вывод: enforce возможен НЕ везде. Стратегия смещается на «enforce-где-можно + forensic watermark + детект + политика».

## Матрица возможностей

| Угроза | Web | Electron-Win | Electron-mac | Android | iOS |
|--------|-----|--------------|--------------|---------|-----|
| **Скриншот** | ❌ IMPOSSIBLE | ✅ ENFORCE (WDA_EXCLUDEFROMCAPTURE)* | ⚠️ DETECT (NSWindowSharingNone сломан) | ✅ ENFORCE (FLAG_SECURE) | ⚠️ DETECT (userDidTakeScreenshot) |
| **Запись экрана** | ❌ IMPOSSIBLE | ✅ ENFORCE* | ⚠️ DETECT (macOS 15 ScreenCaptureKit bypass) | ⚠️ DETECT (MediaProjection callback) | ⚠️ DETECT (UIScreen.isCaptured) |
| **Звукозапись** | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE | ❌ IMPOSSIBLE |

*WDA_EXCLUDEFROMCAPTURE: работает Win10 2004+, но нестабилен на части Win11-билдов (19045 показывает чёрный прямоугольник).

## По платформам
- **Electron Win:** `setContentProtection(true)` → `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` на DWM-уровне. Блокирует BitBlt/DXGI/Windows Graphics Capture, OBS. Гэпы: нестабильность Win11-билдов (#47834), NDI/RTMP на сетевом уровне не остановить.
- **Electron mac:** `NSWindowSharingNone` **полностью неэффективен** против ScreenCaptureKit (macOS 15+) — Apple намеренно изменил compositing. Zoom/OBS обходят. Детект: оранжевый индикатор в menu bar (Sequoia 15+).
- **Android:** `FLAG_SECURE` блокирует скриншоты, recent-apps, non-secure virtual displays (MediaProjection→чёрное). Flutter: `flutter_windowmanager`. Гэпы: rooted-устройства, физическая вторая камера, CVE-2025-32322. Детект: `addScreenRecordingCallback` + initial-state check.
- **iOS:** скриншот **заблокировать нельзя**. Детект: `userDidTakeScreenshotNotification` (post-facto), `UIScreen.isCaptured` + `capturedDidChange` (запись/AirPlay/mirroring). Трюк: `UITextField(isSecureTextEntry:true)` рендерит чёрное в захвате (косметика).
- **Web:** `getDisplayMedia`/скриншот **нельзя блокировать или надёжно детектить**. Митигации: `visibilitychange`→pause+blur (~20-30%, обходится расширением), canvas-watermark, EME/Widevine L1 (только Win Chrome ~70-80%, сложно, латентность). **Для конференции web исключён** (решение проекта).

## Звукозапись = невозможно запретить нигде
Loopback, физический микрофон, rooted. **Единственная митигация — forensic AUDIO WATERMARKING:** неслышимый per-user идентификатор (User/Session/Timestamp) через Spread Spectrum / echo modulation, переживает ре-кодирование. Утечку трассируют до пользователя. Библиотеки: ProveAudio, ScoreDetect, AWT2, Tencent Cloud, кастомный SSW. Эффект-детеррент ~40% снижение утечек.

## Рекомендованная слоистая стратегия
1. **ENFORCE где можно:** Electron/Tauri-Win `setContentProtected`, Android `FLAG_SECURE`, iOS secure-field трюк.
2. **DETECT & DETER:** macOS оранжевый индикатор, Android callback, iOS `isCaptured`, web `visibilitychange`→pause. Лог попыток.
3. **Видимый per-user watermark:** имя+SessionID+timestamp, overlay, низкая прозрачность. Психологический детеррент.
4. **Forensic аудио-watermark:** неслышимый per-user, трассировка утечки.
5. **Политика + юр.уведомление:** «запись запрещена, всё watermarked, нарушители идентифицируются».
6. **Мониторинг:** session-логи, anomaly-детект, risk-scoring root/jailbreak.

## Фундаментально недостижимо (управлять ожиданиями)
Физическая вторая камера снимает экран · rooted/jailbroken · аудио-loopback · web-скриншот OS-средствами · macOS ScreenCaptureKit · Widevine не на Win/Chrome · браузер-расширения отключают Page Visibility.

**Перевод ТЗ честно:** скриншот/запись — блокируемо на Win+Android, детект на iOS/mac, невозможно на web; **звук — нигде не блокируемо** → watermark+трассировка. Сдвиг с «prevent» на «detect, identify, prosecute».

## Источники
- https://www.electronjs.org/docs/latest/api/browser-window
- https://github.com/electron/electron/issues/47834
- https://github.com/tauri-apps/tauri/issues/14200
- https://developer.android.com/reference/android/view/WindowManager.LayoutParams
- https://pub.dev/documentation/flutter_windowmanager/latest/
- https://zeropath.com/blog/android-cve-2025-32322-mediaprojection-bypass
- https://developer.apple.com/documentation/uikit/uiscreen/iscaptured
- https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API
- https://www.vdocipher.com/blog/screen-capture-block-video/
- https://proveaudio.com/ · https://www.scoredetect.com/blog/posts/ai-watermarking-live-streaming-how-it-works
- https://engineering.fb.com/2025/11/04/video-engineering/video-invisible-watermarking-at-scale/
