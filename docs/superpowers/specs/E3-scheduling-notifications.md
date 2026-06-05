# E3 — Планирование + Уведомления

> **Статус:** план-спек (далёкая фаза; детализируется перед началом Фазы 4). Greenfield.
> **Источники:** мастер-план §4 (E3), [ROADMAP.md](../../ROADMAP.md), ADR [D-004](../../ARCHITECTURE_DECISIONS.md) (Phoenix/Oban), [D-006](../../ARCHITECTURE_DECISIONS.md) (auth-hook).

---

## Цель

Дать организаторам возможность **планировать встречи** (включая повторяющиеся), видеть **календарь** в web-панели и автоматически **рассылать уведомления/напоминания** участникам по нескольким каналам. Закрывает пункты ТЗ: «Система уведомлений + планирования», «Календарь».

---

## Scope (пункты ТЗ → задачи)

- **Recurring meetings** — повторяющиеся встречи (daily/weekly/monthly, дни недели, до даты/N повторений, исключения-overrides отдельных экземпляров).
- **Календарь-UI** (LiveView) — месяц/неделя/день, RBAC-scoped (Manager видит своё поддерево департаментов), фильтры по департаменту/организатору/статусу.
- **Напоминания** — запланированные через Oban (за 24ч / 1ч / 10мин — конфигурируемо), идемпотентные, с дедупликацией.
- **Каналы уведомлений** — адаптеры: **email**, **SMS**, **Telegram**, **in-app push** (в Tauri-клиент через WS/Channel). Единый behaviour, pluggable.
- **Приглашения с подтверждением** — invite → accept/decline/tentative (RSVP), статус приглашения отражается в ростере (связь с `meeting_invitees` из E2).
- **`.ics`-экспорт** — генерация iCalendar для импорта во внешние календари (Outlook/Google), включая VEVENT с RRULE для recurring.

---

## Ключевые задачи

1. **Recurrence-движок:** хранение правила (RFC 5545 RRULE-подобно) + материализация экземпляров (виртуальные vs персистентные — см. Открытые вопросы). Кандидат-библиотеки для RRULE/`.ics` — проверить через Context7 перед выбором (НЕ гадать API).
2. **Календарь LiveView:** компонент-сетка, навигация по периодам, drag-to-reschedule (опционально, JS hook), live-обновление через PubSub при изменениях.
3. **Notification context** (`svc_core`): `Notifications` — единый API `deliver/2`, очередь Oban, шаблоны (i18n: ru/uz), tracking статуса доставки.
4. **Channel-адаптеры** (behaviour `Notifications.Channel`): `Email`, `SMS`, `Telegram`, `InAppPush`. Каждый — отдельный Oban worker/queue с retry+backoff. Конфиг каналов per-org (jsonb settings).
5. **Reminder-scheduler:** при создании/изменении встречи — (пере)планировать Oban-джобы напоминаний (`scheduled_at`), отмена при удалении/переносе.
6. **RSVP-флоу:** endpoint/LiveView для accept/decline (+ подписанная ссылка из email/Telegram), обновление `meeting_invitees`, audit.
7. **`.ics`-генератор:** VCALENDAR/VEVENT + VALARM + RRULE; вложение в email, download в web.
8. **Audit:** все рассылки и RSVP → `audit_logs` (сквозной слой E0).

---

## Технический подход

- **Планировщик:** **Oban** (уже в стеке, [D-004]) — `Oban.insert` со `scheduled_at` для напоминаний; `Oban.Cron`/periodic — для материализации recurring-экземпляров на горизонт (rolling window, напр. +60 дней).
- **Каналы как behaviour:** один `@callback deliver(notification, recipient, opts)`; реестр адаптеров; новый канал = новый модуль без правки ядра. Идемпотентность через `unique` Oban-джобы (по `{meeting_id, user_id, reminder_kind}`).
- **Email:** Swoosh (де-факто для Phoenix) — адаптер уточнить (SMTP гос-почты vs API). **SMS/Telegram:** HTTP через **Finch** (тот же клиент, что для LiveKit, [D-004 окружение]); провайдеры — открытый вопрос (гос-требования к каналам).
- **In-app push:** Phoenix Channel/Presence → Tauri-клиент (WS уже есть для управления); fallback-баннер в web-панели.
- **RRULE/.ics:** материализация — гибрид: правило хранится один раз, экземпляры разворачиваются lazily для отображения + персистятся только при per-instance override (cancel/reschedule одного вхождения).
- **i18n:** Gettext (ru/uz) для шаблонов уведомлений.

---

## Предварительные доменные сущности (Ecto)

> Уточняются перед фазой. Все таблицы несут `org_id` ([D-005]).

- **meeting_recurrences** `(id, org_id, meeting_id?, organizer_id, title, freq [daily|weekly|monthly], interval, by_weekday [array], dtstart, until, count, exdates [array], timezone, recording_policy, late_threshold_seconds)` — шаблон серии.
- **meetings** (расширение E2-таблицы): `+recurrence_id (fk, nullable)`, `+recurrence_instance_date`, `+overridden (bool)` — материализованный экземпляр серии.
- **meeting_invitees** (расширение E2): `+rsvp_status [pending|accepted|declined|tentative]`, `+rsvp_at`, `+invite_token` — подтверждение.
- **notifications** `(id, org_id, user_id, meeting_id?, channel [email|sms|telegram|in_app], kind [invite|reminder|update|cancel|rsvp_request], payload jsonb, status [pending|sent|failed|delivered], scheduled_at, sent_at, error, attempts)` — журнал/очередь рассылок.
- **notification_preferences** `(id, org_id, user_id, channel, kinds [array], enabled)` — opt-in/opt-out на пользователя (открытый вопрос: разрешён ли opt-out для гос-обязательных уведомлений).
- *(конфиг каналов per-org — в `organizations.settings` jsonb или отдельная `notification_channel_configs`).*

---

## Риски

- **Каналы для гос — открытый вопрос (из мастер-плана):** допустима ли гос-почта/SMS-провайдер/Telegram с т.з. безопасности и комплаенса? Telegram = внешний сервис (противоречит «Max Data Security Private»?). Требует решения заказчика **до** реализации адаптеров.
- **Recurring сложность:** edge-cases (DST-переходы, перенос одного экземпляра серии, удаление «этого и последующих») — классический источник багов; нужен тщательный TDD.
- **Доставляемость SMS/email** в гос-инфраструктуре (спам-фильтры, лимиты провайдера).
- **Идемпотентность напоминаний** при реплее Oban / пересоздании джоб после переноса встречи.
- **Timezone:** хранить UTC, отображать в TZ организации/пользователя; recurring особенно чувствителен.

---

## Зависимости

- **E0** (Фундамент) — orgs/users/RBAC/audit/Oban, department-иерархия для scoping календаря.
- **E2** (Посещаемость) — `meetings`, `meeting_invitees` (ростер расширяется RSVP), профили (контакты: phone/email для каналов).
- *(косвенно)* **E1** — `meetings.livekit_room_name` (ссылка «войти» из приглашения/напоминания).

---

## Открытые вопросы

1. **Каналы для гос:** какие каналы санкционированы? Telegram допустим (внешний сервис) или только on-prem email/SMS? Какой SMS-провайдер (Eskiz/Play Mobile/гос-шлюз)?
2. **Гос-почта:** SMTP-сервер ведомства или внешний API? Реквизиты, лимиты.
3. **Opt-out:** разрешён ли пользователю отключать обязательные уведомления, или они принудительны (гос-дисциплина)?
4. **Recurring-материализация:** rolling-window-горизонт (сколько вперёд разворачивать)? Политика «этот / этот и будущие / вся серия» при правках.
5. **Внешний календарь:** нужна ли двусторонняя CalDAV-синхронизация, или достаточно одностороннего `.ics`-экспорта?
6. **RSVP-обязательность:** влияет ли decline на расчёт посещаемости (excused absence vs absent)?
