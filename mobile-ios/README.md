# SVC — iOS klient (SwiftUI)

Android ilovasi (`../mobile`) bilan bir xil funksiya va dizayn: landing → login →
4 bo'lim (Uchrashuvlar / Xabarlar / Bo'lim / Profil) + majlis yaratish.

## Holat

| Qism | Holat |
|---|---|
| Landing, login (2FA bilan), auto-login | ✅ yozilgan |
| Uchrashuvlar ro'yxati, majlisga ulanish | ✅ |
| Majlis yaratish + ishtirokchi biriktirish (D-016) | ✅ |
| Xabarlar (o'qilmagan badge, o'qilgan belgilash) | ✅ |
| Bo'lim xodimlari, profil, chiqish | ✅ |
| Skrinshot / ekran-yozuv **aniqlash** + serverga qayd | ✅ |
| LiveKit video | ⬜ 2-bosqich (pastga qarang) |
| Push-bildirishnoma (APNs) | ⬜ rejada |

**Anti-capture farqi (ADR D-013):** iOS'da Android'dagi `FLAG_SECURE` ekvivalenti
**yo'q** — skrinshot/ekran-yozuvni bloklab bo'lmaydi. iOS'da faqat **aniqlash**
mumkin: `UIScreen.isCaptured` (yozuv/translyatsiya) va
`userDidTakeScreenshotNotification` (skrinshot). Aniqlanganda kontent yashiriladi
va hodisa `/api/capture-events` orqali serverga yoziladi.

## Qurish

macOS + Xcode 15+ kerak. `.xcodeproj` git'da saqlanmaydi — `project.yml` dan
generatsiya qilinadi (mo'rt `pbxproj` konfliktlarini oldini oladi):

```bash
brew install xcodegen
cd mobile-ios
xcodegen generate
open SVC.xcodeproj
```

Simulyatorda ishga tushirish: Xcode → Run (⌘R).

### Mac bo'lmasa

`.github/workflows/ios.yml` har push'da **GitHub Actions macOS runner**'ida
kompilyatsiya qiladi va simulyator uchun `SVC.app` artefaktini beradi. Kompilyatsiya
xatolari CI log'ida ko'rinadi.

Haqiqiy iPhone'ga o'rnatish uchun Apple Developer akkaunti kerak
(TestFlight yoki `.ipa` imzolash).

## Server

Manzil UI'da ko'rsatilmaydi — `SvcApi.serverURL` konstantasi
(`https://admin.co1nlist.uz`). Backend bilan bir xil endpointlar:

```
POST /api/login            POST /api/login/totp
GET  /api/me               GET  /api/users        GET /api/assignable
GET  /api/meetings         POST /api/meetings
GET  /api/notifications    POST /api/notifications/:id/read
POST /api/meetings/:id/join
POST /api/capture-events
```

Token iOS **Keychain**'da saqlanadi (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).

## 2-bosqich — LiveKit video

Server tomonda media oqimi hozir qurilmalararo o'tmaydi (NAT + Cloudflare tunnel
UDP tashimaydi). LiveKit Cloud ulanganda yoki statik IP olinganda:

1. `project.yml` dagi `packages: LiveKit` blokini oching va
   `dependencies: - package: LiveKit` ni target'ga qaytaring.
2. `Views/CallView.swift` dagi placeholder o'rniga `Room` + `SwiftUIVideoView`.
3. `SvcApi.join(...)` allaqachon `wss://` manzil qaytaradi (ATS talabi).

## Tuzilma

```
mobile-ios/
├── project.yml              # XcodeGen spec
└── SVC/
    ├── SVCApp.swift         # @main + AppState (sessiya)
    ├── SvcApi.swift         # REST klient + modellar
    ├── Prefs.swift          # Keychain (token)
    ├── Geo.swift            # E7 GPS (best-effort)
    ├── Theme.swift          # Android bilan bir xil ranglar
    └── Views/
        ├── LandingView.swift      LoginView.swift
        ├── HomeView.swift         MeetingsView.swift
        ├── CreateMeetingView.swift
        ├── NotificationsView.swift
        ├── DepartmentView.swift   ProfileView.swift
        └── CallView.swift         # + CaptureMonitor
```
