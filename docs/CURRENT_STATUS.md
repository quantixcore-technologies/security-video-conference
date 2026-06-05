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

## ⏭️ СЛЕДУЮЩИЙ КВЕСТ (выбран Otabek): Расширенные контролы звонка
Файл: `apps/svc_web/lib/svc_web/controllers/call_html/show.html.heex` (standalone HTML+LiveKit JS).
Добавить во время звонка:
- screen-share (`room.localParticipant.setScreenShareEnabled(true)`) + кнопка
- боковая панель списка участников + индикатор говорящего (ActiveSpeakersChanged)
- mute-индикаторы каждого участника (TrackMuted/Unmuted)
- fullscreen, выбор камеры/микрофона (enumerateDevices)
- чат в звонке (room.localParticipant.publishData)
> Спека: `docs/superpowers/specs/E5-anti-capture.md` (звонок-клиент) + backlog.

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

## 📋 Backlog (docs/BACKLOG.md — feedback Otabek)
i18n RU/UZ/EN · Tauri-клиент · реальный LiveKit Egress · E3/E4/E5/E6/E7 · OneID/E-IMZO.

## ❓ Открытые вопросы заказчику
Комплаенс O'zDSt/СКЗИ · парк Windows · каналы уведомлений E3 · смысл «CRM»(E4) · mobile-стек · хранение записей.

## 📚 Ключевые доки
ADR: `docs/ARCHITECTURE_DECISIONS.md` (14) · разведка: `docs/research/` (4) · спеки: `docs/superpowers/specs/E0-E7` · итоги: `docs/sessions/2026-06-05.md` · `CLAUDE.md`(навигация).
