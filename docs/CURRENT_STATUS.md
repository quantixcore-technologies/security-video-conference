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

## ✅ Сделано после редизайна (53 коммита, 154 теста 0 failures)
- Расширенные контролы звонка (screen-share, участники+говорящий, чат, mute, fullscreen, устройства).
- Профиль-рефактор: top-right avatar dropdown + `/admin/profile` (дублирование убрано).
- **UX-аудит P0+P1+P2 закрыт** (`docs/UX-AUDIT.md`): управление сотрудниками/встречами + карточка `users/:id`, 2FA enrollment (QR/eqrcode), mobile-бургер, emerald loading-bar, повтор пароля, поиск/фильтр/пагинация таблиц, локализация статусов/действий, a11y (alt).
- **Эпик E3 (A–F)** — планирование: уведомления+колокольчик · напоминания (Oban T-24ч/1ч) · календарь (месяц) · RSVP · recurring-встречи · `.ics`-экспорт. _(внешние каналы email/SMS/Telegram — blocked заказчиком)._
- **E5 анти-захват (A+B):** per-user watermark на звонке · юр-баннер · `capture_events` журнал + API `/api/capture-events` · `SecurityLive` (`/admin/security`) · матрица. _(ENFORCE setContentProtected/FLAG_SECURE — Tauri/mobile-фаза)._
- **E7 сеть/гео (A+B):** pre-join gate + `Svc.Geo` (classify_ip RFC1918, журнал) · **гео-политика per-org** (`geo_policies`: mode off/flag_only/enforce, allowed_countries, whitelist_ips, block_vpn/proxy) · полная security-панель `/admin/security` (политика + журнал захвата + журнал гео). _(реальный VPN/country = MaxMind MMDB через locus, открытый вопрос лицензии)._

## ⏭️ СЛЕДУЮЩИЙ КВЕСТ (на выбор Otabek)
- **E5-C:** anti-capture политика per-meeting (watermark on/off, реакция warn/eject).
- **E7-C:** `locus`/MaxMind интеграция (реальный country+VPN-детект) — нужна MMDB-лицензия.
- **E6** ML-liveness/deepfake (Python+Rust ML-сервис) · **Tauri** desktop-клиент (prod-видео+enforce setContentProtected) · **i18n** RU/UZ/EN.
> Открытые вопросы заказчику: MaxMind-лицензия · каналы уведомлений (E3) · парк Windows · kiosk/TPM (E5) · allowed-countries/whitelist (E7).

## ⚠️ Локальный запуск (КРИТИЧНО)
```bash
docker compose -f deploy/livekit/docker-compose.yml up -d   # LiveKit :7880
# Postgres docker svc-postgres :5434 (brew-postgres@17 на 5432!) — префикс DB_PORT=5434
DB_PORT=5434 mix phx.server                                  # :4000, admin/AdminPass12345
DB_PORT=5434 mix test                                        # 104 теста
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
