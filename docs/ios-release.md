# iOS релиз — playbook (App Store / TestFlight)

> Код iOS-клиента готов (паритет с Android, CI-сборка зелёная). Единственный
> блокер — **Apple Developer аккаунт ($99/год)**: без него iPhone не поставит
> приложение вообще (в отличие от Windows/macOS, где неподписанное ставится с
> предупреждением). Этот документ — что делает **заказчик** (аккаунт/оплата) и
> что делает **разработчик** (подпись/CI/выкладка).
>
> Данные приложения: bundle `uz.svc` · iOS 16+ · версия 0.1.0 (build 1) ·
> разрешения: камера, микрофон, геолокация (при использовании).

## Шаг 1 — Apple Developer аккаунт  ← ТОЛЬКО ЗАКАЗЧИК

1. **D-U-N-S номер** для юрлица (QuantixCore Technologies MChJ) — бесплатно на
   `developer.apple.com/enroll/duns-lookup`. Если номера нет — Apple заведёт его
   (1–5 рабочих дней). Для организации нужен именно D-U-N-S; для individual —
   не нужен, но тогда в App Store продавец = физлицо.
2. **Enrollment**: `developer.apple.com/programs/enroll` → Organization → оплата
   **$99/год**. Apple проверяет юрлицо (может позвонить/написать) — 1–3 дня.
3. Получаете доступ к **App Store Connect** (`appstoreconnect.apple.com`).

> Почему нельзя иначе: бесплатный Apple ID + Xcode ставит приложение только на
> СВОЙ телефон на 7 дней и требует Mac с подключённым iPhone — у нас нет ни Mac,
> ни устройства, ни способа распространять. Поэтому только платный аккаунт.

## Шаг 2 — сущности в портале  ← заказчик (разработчик подскажет каждый клик)

В App Store Connect / Developer portal создать:
- **App ID** `uz.svc` (Certificates, IDs & Profiles → Identifiers). Capabilities:
  по умолчанию (камеры/микрофона/гео capability не требуют — только Info.plist-строки, уже есть).
- **Distribution-сертификат** (Apple Distribution) → экспортировать как **`.p12`** с паролем.
- **Provisioning profile** (App Store) на App ID `uz.svc` → скачать `.mobileprovision`.
- **App Store Connect API key** (Users and Access → Integrations → App Store Connect API):
  Issuer ID, Key ID, файл **`.p8`** (для загрузки в TestFlight из CI без пароля Apple ID).
- **Новое приложение** в App Store Connect: имя «SVC — Security Video Conference»,
  bundle `uz.svc`, язык — узбекский (+ русский/английский по желанию).

## Шаг 3 — секреты в GitHub  ← заказчик даёт файлы, разработчик заводит секреты

В репозитории Settings → Secrets and variables → Actions добавить (base64 для файлов):
```
IOS_DIST_CERT_P12         # base64 .p12
IOS_DIST_CERT_PASSWORD    # пароль от .p12
IOS_PROVISION_PROFILE     # base64 .mobileprovision
ASC_API_KEY_ID            # Key ID
ASC_API_ISSUER_ID         # Issuer ID
ASC_API_KEY_P8            # base64 .p8
```
base64: `base64 -w0 файл` (Linux) → скопировать вывод в секрет.

## Шаг 4 — подпись и выкладка в CI  ← РАЗРАБОТЧИК

Добавляется workflow `.github/workflows/ios-release.yml` (`workflow_dispatch`,
активен только когда секреты заданы). Логика на macos-runner:
1. импорт `.p12` во временный keychain, установка provisioning profile;
2. `xcodegen generate`;
3. `xcodebuild -scheme SVC archive` → `-exportArchive` с `ExportOptions.plist`
   (`method: app-store`, `teamID`, автоподпись профилем);
4. загрузка `.ipa` в TestFlight: `xcrun altool --upload-app -f SVC.ipa --type ios
   --apiKey $ASC_API_KEY_ID --apiIssuer $ASC_API_ISSUER_ID` (ключ `.p8` в
   `~/private_keys/AuthKey_<KeyID>.p8`).

Готовый workflow разработчик добавит и прогонит, когда появятся секреты
(сейчас его нет — без реальных сертификатов он бы всё равно падал).

## Шаг 5 — метаданные App Store  ← черновик готов, заказчик утверждает

- **Имя:** SVC — Security Video Conference. **Подзаголовок:** Suveren, xavfsiz video-aloqa.
- **Категория:** Business (втор. — Productivity).
- **Описание (uz/ru/en):** self-hosted, суверенная платформа для гос/корп-встреч;
  видео/аудио (LiveKit), экран, чат; anti-capture (detection на iOS — Apple не даёт
  блокировать), RBAC, аудит, гео-политика. Честно: канал DTLS-SRTP, E2EE (SFrame) — в roadmap.
- **Приватность (Nutrition Labels):** приложение использует камеру, микрофон,
  геолокацию (при использовании) — для видеозвонка и гео-политики безопасности;
  данные не продаются, не используются для трекинга; хранятся на сервере организации.
- **Скриншоты:** 6.7"/6.5"/5.5" iPhone — снять на симуляторе из CI-сборки (можно
  автоматизировать) или взять из существующих Android-аналогов по компоновке.
- **Экспортное соответствие:** `ITSAppUsesNonExemptEncryption = false` уже стоит
  (используем только стандартный HTTPS/DTLS — освобождено).

## Шаг 6 — TestFlight → App Store

- **TestFlight** (рекомендуется первым): после загрузки .ipa — до 90 дней,
  внутренние (до 100) и внешние (до 10 000) тестировщики; внешние проходят лёгкий
  Beta App Review (обычно < 1 дня). Тестировщики ставят через приложение TestFlight.
- **App Store** (публичный релиз): submit for review → полный App Review (~1–3 дня).
  После одобрения — доступно всем в App Store.

## Разделение ответственности

| Что | Кто |
|---|---|
| Apple Developer аккаунт, D-U-N-S, оплата $99, проверка юрлица | **Заказчик** |
| Сертификаты/профили/ключи в App Store Connect (по инструкции) | Заказчик (разработчик ведёт по шагам) |
| Секреты в GitHub, workflow подписи, сборка `.ipa`, загрузка в TestFlight | **Разработчик** |
| Метаданные/скриншоты/приватность | Черновик — разработчик; утверждение — заказчик |
| Публикация в App Store, ответы App Review | Совместно |

**Итог:** заказчику — открыть аккаунт (Шаг 1) и создать сущности (Шаг 2, по нашей
инструкции). Всё остальное (подпись, CI, TestFlight, стор) делает разработчик.
Код уже готов и собирается на CI.
