# SVC Mobile — нативный Android-клиент

Нативный клиент видеоконференции (E1, D-001): **Kotlin + Jetpack Compose + LiveKit Android SDK** (нативный WebRTC, не webview).

## Почему нативный (не webview/Tauri)
- **D-001:** видео — только нативный клиент.
- **E5 enforce:** `FLAG_SECURE` на экране звонка (`CallActivity`) — блокирует скриншоты и запись экрана средствами Android. На webview это недоступно.
- **E7:** доступ к GPS для гео-кросс-чека (фаза 2).

## Архитектура
- `MainActivity` — экран входа (сервер/логин/пароль/ID встречи).
- `SvcApi` — REST: `POST /api/login` → bearer-токен; `POST /api/meetings/:id/join` → `{url, token, room}`.
- `CallActivity` — LiveKit-комната: подключение, локальное+удалённое видео, mic/cam toggle, `FLAG_SECURE`.

> Бэкенд отдаёт `ws://127.0.0.1:7880`; клиент подменяет loopback-хост на хост сервера
> (с эмулятора хост-машина = `10.0.2.2`).

## Сборка
```bash
export ANDROID_HOME=$HOME/Android/Sdk
cd mobile
./gradlew assembleDebug          # APK → app/build/outputs/apk/debug/
./gradlew installDebug           # установить на подключённое устройство/эмулятор
```

## Запуск
1. Поднять бэкенд + LiveKit (см. корневой `docs/CURRENT_STATUS.md`).
2. Эмулятор: сервер по умолчанию `http://10.0.2.2:4000`. Реальное устройство в той же сети: указать IP хоста.
3. Логин `admin` / `AdminPass12345`, ID встречи `1` → «Войти в звонок».

## TODO (следующие слайсы)
- 2FA (TOTP) через API — сейчас PoC только без 2FA (`totp_required` ошибка иначе).
- GPS-захват для E7 гео-кросс-чека.
- iOS-клиент (Swift, требует macOS).
- Чат/screen-share/участники (паритет с web-call).
