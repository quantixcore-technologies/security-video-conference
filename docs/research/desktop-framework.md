# Разведка: Desktop-фреймворк для secure LiveKit-клиента (E1)

> Источник: research-отряд №4. Контекст: Windows-доминирование, max-security enforce, LiveKit, Rust-экспертиза команды.
> **Вердикт: TAURI.** Electron — RISKY (анти-захват сломан), нативный — NO-GO (нет LiveKit SDK), Flutter-desktop — NOT READY.

## Ранжирование

| Фреймворк | Вердикт | Решающая причина |
|-----------|---------|------------------|
| **🥇 Tauri** | ✅ GO | `setContentProtected()`→нативный `SetWindowDisplayAffinity` (подтв. в `tao`); LiveKit JS SDK работает в WebView2 (Chromium); Rust-бэкенд: детект рекордеров+TPM+kiosk; 10× легче Electron; Rust-экспертиза |
| Electron | ⚠️ RISKY | анти-захват #47834 молча сломан на ~30-40% Windows (Win10 19045, Win11 22000), не фикснут с v36.3.2 |
| Нативный Qt/.NET | ❌ NO-GO | у LiveKit нет нативного SDK → только C++ SDK v1.0.0 (незрелый, без Qt/WinUI-биндингов) или сырой WebRTC с нуля |
| Flutter Desktop | ❌ NOT READY | офиц. `livekit_client` НЕ поддерживает Windows desktop (только iOS/Android/Web); `screen_protector` mobile-only |

## Tauri — детали (GO)
- **Анти-захват:** `setContentProtected()` → Win32 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` через `tao` ([commit 802146f](https://github.com/tauri-apps/tao/commit/802146fb8692a46185846a64163c174520450c43)). Нативный Win32, не web-абстракция. Caveat: WDA не DRM, есть обходы — baseline.
- **WebRTC+LiveKit JS:** WebView2 = Chromium → `getUserMedia` камера/мик работает, multiple streams, screen-share. LiveKit JS — browser-agnostic. ⚠️ Официальной LiveKit+WebView2 доки нет → **MODERATE risk, PoC-спайк обязателен** (камера/мик/screen-share + setContentProtected на Windows). Без showstopper'ов.
- **Rust-бэкенд:** детект рекордеров (`CreateToolhelp32Snapshot` enum процессов — OBS/Camtasia/Bandicam), TPM-attestation, kiosk (Alt+Tab/taskbar), watermark (GDI+), `WinEventHook`. Memory-safe, 10× меньше Electron, fine-grained permissions.

## Electron — RISKY
- #47834 **не исправлен** (июнь 2026): `setContentProtection(true)` молча падает на Win10 19045, Win11 22000 — окно захватывается. ~30-40% целевой базы. Регрессия v36.3.2, нет ETA. Связанные: чёрные прямоугольники при screen-share (#46507), protection сбрасывается `hide()` (#45844).
- LiveKit JS — reference target (зрелый). Но для security-продукта сломанный анти-захват на трети устройств неприемлем без самостоятельного патча Electron (C++).

## Нативный Qt/.NET — NO-GO
- LiveKit нет официального C++/.NET/Qt SDK. Только C++ SDK v1.0.0 (DevPreview, незрелый): CMake+Rust+protobuf+abseil+openssl, без UI-биндингов → строить video-conference UI с нуля на libwebrtc. Security-плюсы (TPM/kiosk/детект) Tauri уже покрывает Rust-бэкендом — 80% нативной безопасности за 20% времени.

## Flutter Desktop — NOT READY
- `livekit_client` desktop Windows не поддерживает (iOS/Android/Web only). `screen_protector` mobile-only. Shared-mobile-codebase — единственный плюс, но Tauri-desktop + Flutter-mobile split чище. Пересмотреть только при офиц. Flutter Desktop SDK.

## Архитектура клиента (Tauri)
```
Frontend (WebView2): LiveKit JS SDK + React/Svelte UI + setContentProtected(true) at startup
Rust Backend (IPC): детект рекордеров · window/focus monitoring · TPM 2.0 · kiosk · watermark GDI+ · WinEventHook
```

## Recorder-детект на Windows
Нативно (Rust): enum процессов/окон (`CreateToolhelp32Snapshot`), мониторинг создания процессов. Web-обёртка не может. Надёжность: детект известных рекордеров по имени процесса — обходится переименованием, но baseline-детеррент.

## Источники
- https://github.com/tauri-apps/tao/commit/802146fb8692a46185846a64163c174520450c43
- https://github.com/electron/electron/issues/47834
- https://github.com/livekit/client-sdk-cpp · https://docs.livekit.io/reference/client-sdk-cpp/
- https://livekit-tutorials.openvidu.io/tutorials/application-client/electron/
- https://pub.dev/packages/livekit_client · https://pub.dev/packages/screen_protector
- https://tech-insider.org/tauri-vs-electron-2026/
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
