# Current Status — Security Video Conference

> Снимок состояния для следующей сессии / после /compact. Обновлять в конце сессии.

## Срез 1 ГОТОВ + редизайн + профиль ✅ (работает вживую)

### Сессия 2026-06-05 (S1) — с нуля до живого продукта с enterprise-UI
- ✅ **E0** Фундамент: Orgs(иерархия), Accounts(Argon2+TOTP+lockout), Authz(RBAC scoping), Audit(append-only), LiveView-админка.
- ✅ **E1** Ядро: LiveKit self-host(docker), Svc.LiveKit(JWT), Meetings, webhook(HMAC), join-API, **живой видеозвонок** (dev: `/admin/meetings/:id/call`).
- ✅ **E2** Посещаемость: ростер, attendance(статусы), Oban FinalizeWorker, Recordings(Egress-сущность), журнал-UI.
- ✅ **Редизайн «Secure Operations»**: тёмная slate+emerald, IBM Plex, sidebar+heroicons, все 8 страниц переделаны (login/totp/dashboard/users/meetings/show/call), фото-upload, totp Cloak-шифрование, **профиль в sidebar везде** + профиль-карточка на dashboard, карточки участников звонка (аватары).
- ✅ **31 коммит · 104 теста 0 failures**, запушено git.n3xt.uz/legion-cyber-arena (private).
- ✅ Доказано вживую: login→dashboard→встречи→журнал; реальный звонок 2 участника→webhook→авто-посещаемость.

## ✅ Сделано после редизайна (60 коммитов, 169 тест 0 failures)
- Расширенные контролы звонка (screen-share, участники+говорящий, чат, mute, fullscreen, устройства).
- Профиль-рефактор: top-right avatar dropdown + `/admin/profile` (дублирование убрано).
- **UX-аудит P0+P1+P2 закрыт** (`docs/UX-AUDIT.md`): управление сотрудниками/встречами + карточка `users/:id`, 2FA enrollment (QR/eqrcode), mobile-бургер, emerald loading-bar, повтор пароля, поиск/фильтр/пагинация таблиц, локализация статусов/действий, a11y (alt).
- **Эпик E3 (A–F)** — планирование: уведомления+колокольчик · напоминания (Oban T-24ч/1ч) · календарь (месяц) · RSVP · recurring-встречи · `.ics`-экспорт. _(внешние каналы email/SMS/Telegram — blocked заказчиком)._
- **E5 анти-захват (A+B):** per-user watermark на звонке · юр-баннер · `capture_events` журнал + API `/api/capture-events` · `SecurityLive` (`/admin/security`) · матрица. _(ENFORCE setContentProtected/FLAG_SECURE — Tauri/mobile-фаза)._
- **E7 сеть/гео (A+B):** pre-join gate + `Svc.Geo` (classify_ip RFC1918, журнал) · **гео-политика per-org** (`geo_policies`: mode off/flag_only/enforce, allowed_countries, whitelist_ips, block_vpn/proxy) · полная security-панель `/admin/security` (политика + журнал захвата + журнал гео). _(реальный VPN/country = MaxMind MMDB через locus, открытый вопрос лицензии)._

- **E4 поручения/задачи (A+B):** backend `tasks` (creator→assignee, meeting_id, priority, status todo/in_progress/review/done, due_at) · `Svc.Tasks` (create/set_status/board/open_count/can_manage?) · ADR **D-015** («CRM» для гос = поручения+задачи, НЕ sales-CRM) · **Kanban-доска** `/admin/tasks` (4 колонки Новые/В работе/Проверка/Выполнено, карточки с приоритетом/исполнителем/сроком, HTML5 drag-drop через JS-hook, RBAC: руководство двигает — сотрудник видит свои read-only). _(обращения граждан 🔒 заказчик)._

## ⏭️ СЛЕДУЮЩИЙ КВЕСТ: E4-C связь со встречей + уведомление исполнителю
- **E4-C:** поручение из совещания (meeting_id-связь на карточке + кнопка «поручение по итогам» из встречи) + E3-уведомление исполнителю при назначении (`Svc.Notifications.notify`).
- Далее E4: **D** (отчётность: выполнение по исполнителю/отделу/срокам).
- Параллельные опции: E5-C политика захвата · **Tauri-PoC** (🔴 критический путь prod-видео) · E6 ML · i18n.
> Открытые вопросы заказчику собраны в `docs/requirements-interview.md` (6 блоков) — разблокируют E4-обращения, E3-каналы, E5-enforce, E7-MMDB, E6-ML, комплаенс.
> ❌ OneID/E-IMZO — НЕ планируется (D-006, 2026-06-05).

## ⚠️ Локальный запуск (КРИТИЧНО)
```bash
docker compose -f deploy/livekit/docker-compose.yml up -d   # LiveKit :7880
# Postgres docker svc-postgres :5434 (brew-postgres@17 на 5432!) — префикс DB_PORT=5434
DB_PORT=5434 mix phx.server                                  # :4000, admin/AdminPass12345
DB_PORT=5434 mix test                                        # 169 тест 0 failures
DB_PORT=5434 mix run apps/svc/priv/repo/seeds.exs            # демо-данные (6 юзеров)
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
