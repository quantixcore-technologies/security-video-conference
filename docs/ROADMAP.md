# ROADMAP — Security Video Conference

> Дорожная карта 8 эпиков (E0–E7). Порядок по риску и зависимостям. Источник решений: [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md).

```
E0 Фундамент+Аудит ──► E1 Ядро конференций ──► E2 Посещаемость+Личность   ◄── СРЕЗ 1 / Milestone 1
                                                  ├──► E3 Планирование+Уведомления ──► E4 CRM+Kanban   (бизнес)
                                                  └──► E5 Анти-захват · E6 Реальность(ML) · E7 Сеть+Гео (security)
   ═══════════════════ Аудит/Комплаенс — сквозной слой ═══════════════════
```

## Срез 1 / Milestone 1 = E0 + E1 + E2

### E0 — Фундамент + Аудит/Комплаенс
**ТЗ:** RBAC, Maximal Data Security, Защищённый канал.
**Задачи:** umbrella scaffold · Accounts (orgs, departments-иерархия, users) · auth (Argon2id + TOTP 2FA) · RBAC 4+1 роли + department-scoping · сквозной audit-log · `org_id`-изоляция · TLS/at-rest · deploy-каркас K8s.
**Спек:** [specs/E0-foundation.md](superpowers/specs/E0-foundation.md). **Зависит:** —.

### E1 — Ядро конференций
**ТЗ:** Video Conference, Защищённый канал.
**Задачи:** LiveKit self-host (helm) · `livekitex` (JWT+RoomService+webhooks) · Meetings context · Tauri-клиент (WebView2+LiveKit JS) join+A/V+`setContentProtected` · hop-by-hop DTLS-SRTP.
**Риск:** LiveKit+WebView2 (MODERATE) → PoC-спайк первым. **Спек:** [specs/E1-conferencing-core.md](superpowers/specs/E1-conferencing-core.md). **Зависит:** E0.

### E2 — Посещаемость + Личность
**ТЗ:** Контроль сотрудников, Журнал, Фото/ФИО/Номер.
**Задачи:** webhooks→`attendance_records` · статусы (present/late/absent/left_early) · гибрид ростер+ad-hoc · Oban для absent · профили (Фото/ФИО/Номер+enrollment) · журнал-UI (LiveView, RBAC-scoped) · опц. серверная запись (Egress).
**Спек:** [specs/E2-attendance.md](superpowers/specs/E2-attendance.md). **Зависит:** E1.

## Следующие фазы

### E3 — Планирование + Уведомления
**ТЗ:** Уведомления+планирование, Календарь. **Задачи:** recurring meetings · календарь-UI · напоминания (Oban) · каналы (email/SMS/Telegram/in-app push) · `.ics`. **Риск:** каналы для гос — открытый вопрос. **Зависит:** E0, E2.

### E4 — Бизнес-слой (CRM + Kanban)
**ТЗ:** CRM+KANBAN. **Задачи:** Kanban (LiveView drag-drop) · CRM-сущности (смысл «CRM» для гос — собрать требования). **Риск:** размытость «CRM». **Зависит:** E0.

### E5 — Анти-захват
**ТЗ:** Запрет скриншот/звукозапись/запись. **Задачи:** `setContentProtected` (Win) · детект рекордеров (Rust) · видимый watermark · forensic аудио-watermark · Android FLAG_SECURE/iOS isCaptured · kiosk/TPM. **Артефакт:** [security/anti-capture-matrix.md](security/anti-capture-matrix.md). **Зависит:** E1.

### E6 — Подтверждение реальности (ML)
**ТЗ:** Защита от DeepFake. **Задачи:** ML-сервис (Python+Rust/ONNX, GPU) · face-match (InsightFace, приоритет) · liveness (MiniFASNet) · deepfake (R&D) · кадры через Egress. **Риск:** deepfake research-grade. **Зависит:** E1, E2.

### E7 — Сеть + Гео
**ТЗ:** GPS, ГЕО-блок, нет VPN. **Задачи:** VPN-детект (MaxMind+Locus) · гео-блок (Country+GPS) · GPS (mobile) · pre-join gate. **Риск:** GPS только mobile. **Зависит:** E0, mobile.

## Фазы реализации
- **Фаза 0:** документация + каркас + LiveKit local/K8s
- **Фаза 0.5:** 🔬 PoC-спайк Tauri+WebView2+LiveKit
- **Фазы 1-3:** Срез 1 (E0→E1→E2) — Milestone 1
- **Фаза 4:** E3 · **Фаза 5:** E4 · **Фаза 6:** E5 · **Фаза 7:** E6 · **Фаза 8:** E7 (+ mobile)

Каждая фаза: спек → TDD-код → тесты → документация → commit.
