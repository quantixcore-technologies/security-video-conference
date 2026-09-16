# RUNBOOK — эксплуатация SVC (production)

> Практическая шпаргалка «как работает прод и что делать, когда». Дополняет
> `CURRENT_STATUS.md` (где остановились) и `ARCHITECTURE_DECISIONS.md` (почему так).
> Последнее обновление: 2026-09-16.

## 1. Что где живёт

| Что | Где |
|---|---|
| Прод-хост | `shuxrat@ssh.co1nlist.uz` через Cloudflare-туннель (`ssh coinlist`) |
| Приложение (backend+веб) | systemd `svc-real.service` — **собранный prod-релиз** `~/svc-real/_build/prod/rel/svc/bin/svc start` |
| Код на сервере | `~/svc-real` (рабочая копия; обновляется копированием файлов, не `git pull`) |
| Env (секреты) | `~/svc-real.env` (600): `SECRET_KEY_BASE`, `CLOAK_KEY`, `CHECK_ORIGIN`, `PHX_SERVER`, `PORT=4000`, `PHX_HOST`, `DATABASE_URL`, `RELEASE_TMP`, `DB_*`, `LIVEKIT_*`, `SVC_ADMIN_PASS`, `APP_RELEASE_MANIFEST_URL` |
| БД | native PostgreSQL 18 (`postgresql@18-main`), база `svc`, роль `svc` |
| Видео | LiveKit **Cloud** (`wss://quantixcore-2mcrpdkd.livekit.cloud`) — медиа идёт мимо туннеля |
| Landing + APK | статикой из `/var/www/landing` (nginx), APK+`version.json` в `downloads/` |
| Nginx | `127.0.0.1:8090` по server_name; `admin.co1nlist.uz`→:4000, `/dev/`→404 |
| Мониторинг | Telegram-бот `@server_linux_robot_bot` (systemd `status-bot`) — 24/7 |
| Бэкап | Borg-репо `/mnt/backup/borg`, ежечасно (`svc-backup.timer` → `svc-backup.service`) |
| Домены | всё на co1nlist.uz и neti.uz (один туннель, nginx по server_name) |

## 2. Проверить, что всё живо

```bash
ssh coinlist 'systemctl is-active svc-real nginx cloudflared postgresql@18-main'
curl -s -o /dev/null -w '%{http_code}\n' https://admin.co1nlist.uz/login          # 200
curl -s https://admin.co1nlist.uz/api/assistant/suggestions -o /dev/null -w '%{http_code}\n'  # 401 (без токена — норма)
# Полная таблица 16 адресов:
bash ~/Shuxrat/svc_stage/server_watch.sh --once
```
Процесс приложения должен быть `beam.smp` (релиз), не `mix`:
`ssh coinlist 'ps -o comm= -p $(systemctl show -p MainPID --value svc-real)'`

## 3. Деплой новой версии (backend/веб)

Прод — **собранный релиз** (не dev-`mix phx.server`). Собирать можно прямо в `~/svc-real`
(`_build/prod` не мешает работающему процессу до рестарта).

```bash
# 1. Скопировать изменённые файлы в ~/svc-real (обычно tar-pipe по ssh).
# 2. На сервере:
cd ~/svc-real
set -a; . ~/svc-real.env; set +a
export MIX_ENV=prod PHX_HOST=admin.co1nlist.uz
export DATABASE_URL="ecto://$DB_USER:<url-encoded DB_PASS>@$DB_HOST:$DB_PORT/$DB_NAME"
mix deps.get --only prod </dev/null      # если менялись зависимости
mix compile </dev/null
mix assets.deploy </dev/null             # если менялись assets
rm -rf _build/prod/rel/svc.prev && cp -a _build/prod/rel/svc _build/prod/rel/svc.prev   # бэкап для отката
mix release svc --overwrite </dev/null
sudo systemctl restart svc-real.service
# 3. Проверить: curl .../login → 200; при провале — откат (см. §4).
```
> ⚠️ Все `mix` внутри `ssh … <<REMOTE` — с `</dev/null` (иначе `mix` съедает stdin-скрипт).
> Прод-SSH из Claude Code работает только в **manual-режиме**; пароль в `~/.secrets/server_pass`.
> `deploy_update.sh` для лендинга НЕ гонять вслепую — staging-лендинг старее серверного.

### Миграции БД (в релизе mix недоступен)
```bash
_build/prod/rel/svc/bin/svc eval "Svc.Release.migrate()"
```

## 4. Откат
```bash
cd ~/svc-real
rm -rf _build/prod/rel/svc && mv _build/prod/rel/svc.prev _build/prod/rel/svc
sudo systemctl restart svc-real.service
```
Полный откат в dev-режим (аварийный): `sudo cp ~/svc-real.service.devmode.bak
/etc/systemd/system/svc-real.service && sudo systemctl daemon-reload && sudo systemctl restart svc-real`.
Бэкап env перед релизным переходом: `~/svc-real.env.bak.prerelease`.

## 5. Бэкап и восстановление

**Бэкап:** ежечасно, Borg-репо `/mnt/backup/borg`. Содержимое: весь `/` (минус кэши/tmp) +
`pg_dumpall` в `var/backups/svc-db/all-databases.sql.gz`. Хранение: 48 ч / 14 д / 8 нед / 12 мес.
Скрипт `/usr/local/sbin/svc-backup.sh`. Пароль репозитория — в отдельном файле
`/etc/borg/passphrase` (600, root:root), скрипт берёт его через `BORG_PASSCOMMAND='cat /etc/borg/passphrase'`
(в самом скрипте пароля больше нет). При переносе на новый хост восстановить и этот файл.

```bash
# Список архивов / последний:
sudo bash -c 'source <(grep -E "^export (BORG_REPO|BORG_PASSCOMMAND)=" /usr/local/sbin/svc-backup.sh); borg list --last 5'
```

**Восстановление БД (проверено 2026-09-16 — счётчики совпали с живыми, без касания прода):**
```bash
sudo bash -c '
  source <(grep -E "^export (BORG_REPO|BORG_PASSCOMMAND)=" /usr/local/sbin/svc-backup.sh)
  cd /tmp && rm -rf rt && mkdir rt && cd rt
  LAST=$(borg list --last 1 --format "{archive}")
  borg extract "::$LAST" var/backups/svc-db/all-databases.sql.gz        # достаём дамп
  # В ПУСТУЮ временную БД (НЕ в прод!):
  sudo -u postgres psql -c "CREATE DATABASE svc_restore_test;"
  # секцию БД svc из pg_dumpall:
  zcat var/backups/svc-db/all-databases.sql.gz | awk "/^\\\\connect / {g=(\$2==\"svc\"); if(g) next} g" \
    | sudo -u postgres psql -d svc_restore_test
  sudo -u postgres psql -d svc_restore_test -c "select count(*) from users;"   # сверить
  sudo -u postgres psql -c "DROP DATABASE svc_restore_test;"                    # убрать
'
```
Полное восстановление на новый хост: `borg extract` нужных путей (`home/shuxrat/svc-real`,
`var/www/landing`, `etc/...`) + восстановить дамп в чистый кластер (`zcat … | psql -U postgres`).

## 6. Мониторинг и инциденты

- **Telegram-бот** `@server_linux_robot_bot` (systemd `status-bot`, юзер `statusbot`) — статус по
  кнопкам + Mini App с графиками + авто-алерты (сервис упал, сайт недоступен, диск/RAM ≥90%, бэкап,
  ребут). Может рестартить **только** 11 сервисов из allowlist (polkit `60-status-bot.rules`), без sudo.
  Логин по паролю; исходники `~/Project/server-status-bot`, деплой — Gitea private.
- **Сессионный вотчер** (только когда открыт Claude Code + ноут онлайн): `server_watch.sh` через Monitor.
- **Логи приложения:** `journalctl -u svc-real -f` (юзер `shuxrat` в `adm` — читается без sudo).
  Nginx-доступ: `/var/log/nginx/access.log` (все vhost'ы в одном; `okhttp` = Android-клиент).

**Частые операции:** рестарт `sudo systemctl restart svc-real`; версия Android — правкой
`/var/www/landing/downloads/version.json` + новый APK (см. `release_apk.sh`), уведомление уходит
само (D-020, Oban cron раз в 10 мин). После релиза вручную пользователям НЕ рассылать.

## 7. Осознанные ограничения (для приёмки)

- Один хост, один Postgres (нет HA), медиа зависит от LiveKit Cloud. Для гос-нагрузки — план масштабирования.
- iOS: код-паритет + CI зелёный, но установка на iPhone требует Apple Developer ($99).
- Комплаенс O'zDSt/СКЗИ, внешние каналы (SMS/email), MaxMind GeoIP — открытые вопросы заказчику.
- `mix hex.audit` на 2026-09-16 чист. База advisory экосистемы обновляется постоянно —
  прогонять `mix hex.audit` периодически и подтягивать патчи зависимостей.
