# E7 — Сеть + Гео (VPN-детект / гео-блок / GPS)

> **Статус:** план-спек (далёкая фаза; детализируется перед Фазой 8; GPS-часть зависит от mobile-клиента). Greenfield.
> **Источники:** [research/livekit-selfhost-e2ee.md](../../research/livekit-selfhost-e2ee.md) §5–6, ADR [D-012](../../ARCHITECTURE_DECISIONS.md) (MaxMind+Locus, self-host), [D-001](../../ARCHITECTURE_DECISIONS.md) (нативный клиент), мастер-план §4 (E7).

---

## ⚠️ Честная рамка

> Из [livekit-selfhost-e2ee.md](../../research/livekit-selfhost-e2ee.md) §5–6 и [D-012]:
> - **VPN-детект:** MaxMind GeoIP2 Anonymous IP + Elixir `locus` (читает MMDB локально, **без внешних API** — под «Max Data Security Private»). Точность: VPN-провайдеры 95%+, **residential proxy ~70-80%** (сложнее), false-positives (корп.прокси/CDN/тетеринг).
> - **GPS точен только на mobile** (desktop GPS ненадёжен) → GPS-функции зависят от mobile-клиента (фаза 2, [D-012] последствие).
> - **GPS-spoofing на rooted — нет идеальной защиты** → слоистые проверки (IP+GPS кросс-чек).

---

## Цель

Гарантировать, что участник подключается из разрешённой сети (без VPN/proxy) и геолокации (Узбекистан), с кросс-проверкой IP↔GPS. **Pre-join gate** блокирует/флагует до входа в конференцию. Закрывает пункты ТЗ: «GPS Локация», «ГЕО-блок», «проверка сети (нет VPN)».

---

## Scope (пункты ТЗ → задачи)

- **VPN/proxy-детект:** MaxMind GeoIP2 Anonymous IP (self-host через `locus`) → VPN/proxy/Tor/hosting flag.
- **Гео-блок:** MaxMind GeoIP2 Country → страна по IP; allowed = Узбекистан; вне → block.
- **GPS-локация** (mobile, фаза 2): device GPS → lat/lon → country; кросс-чек с IP-страной.
- **Pre-join gate:** перед выдачей LiveKit-JWT (E1) — проверка → block / allow / flag (доп.auth).
- **Spoofing-детект:** IP(datacenter/ASN) ↔ GPS-континент mismatch → флаг.
- **Лог/audit:** все gate-решения → `audit_logs`, журнал отказов.

---

## Ключевые задачи

1. **Geo context** (`svc_core`): `Geo` — чтение MMDB через **`locus`** (auto-update daily), `country_from_ip/1`, `anonymous_ip_info/1` (VPN/proxy/Tor/hosting).
2. **MMDB-инфраструктура:** загрузка/обновление GeoIP2 Country + Anonymous IP баз (лицензия MaxMind), `locus` loader, fallback при недоступности базы.
3. **Pre-join gate** (интеграция с E1): hook в JWT-выдаче — `network_geo_check(ip, gps?)` → `{:allow | :block | :flag, reason}`; block → отказ join + понятное сообщение; flag → доп.шаг (доп.auth/уведомление Security Officer).
4. **GPS-захват** (mobile, фаза 2): `navigator.geolocation`/native → lat/lon → reverse-geocode-to-country (offline-датасет границ или MaxMind) → кросс-чек.
5. **Spoofing-логика:** ASN/datacenter-флаг + GPS-континент mismatch → подозрение (VPN+GPS-spoof vs реальная поездка) → flag/доп.auth.
6. **Политика per-org:** allowed-countries, режим (enforce block / flag-only / off), исключения (whitelist корп.IP/ASN против false-positive).
7. **Журнал/UI:** журнал gate-решений (Security Officer), метрики отказов, ложные срабатывания.
8. **False-positive-обработка:** whitelist корп.прокси/CDN/тетеринг (research: известный источник FP).

---

## Технический подход

- **Self-host, без внешних API** ([D-012], [livekit-selfhost-e2ee.md] §5): **MaxMind GeoIP2** (Anonymous IP + Country MMDB) + Elixir **`locus`** (`hexdocs.pm/locus`, читает MMDB локально, auto-update) — версия/API проверить через Context7 перед стартом.
- **IP-источник:** реальный client-IP из JSON-API запроса Tauri-клиента (учесть proxy-заголовки/реальный remote_ip в Phoenix-эндпоинте; on-prem — обычно прямой).
- **Гео-блок:** `ip_country ∉ allowed → block` (research §6). GPS-кросс-чек: `gps_country ≠ ip_country → flag` (VPN+spoof или поездка) → доп.auth.
- **Spoofing-детект (research §6):** datacenter/ASN-флаг (из Anonymous IP) + GPS-континент mismatch. **GPS-spoof на rooted — нет идеальной защиты** → слоистые проверки, не единичная.
- **Pre-join gate:** выполняется в Phoenix **до** `livekitex` JWT-выдачи (E1-флоу §7 мастер-плана: «join → Phoenix RBAC+ростер-чек → JWT»); E7 добавляет network/geo-чек в ту же цепочку.
- **GPS [D-012] последствие:** только mobile (desktop ненадёжен) → desktop-фаза = IP-only гео+VPN; полный IP+GPS кросс-чек — с mobile-клиентом (фаза 2).
- **Точность (честно, research §5):** VPN 95%+, residential proxy ~70-80%, FP на корп.прокси/CDN/тетеринг → whitelist + flag-режим как мягкая опция. Коммерческие (лучше residential): IPQualityScore/Spur (on-prem)/MaxMind Anonymous Plus — если точности мало.

---

## Предварительные доменные сущности (Ecto)

> Все таблицы несут `org_id` ([D-005]).

- **network_geo_checks** `(id, org_id, meeting_id?, user_id, ip, ip_country, is_vpn bool, is_proxy bool, is_tor bool, is_hosting bool, gps_lat?, gps_lon?, gps_country?, decision [allow|block|flag], reason, mmdb_version, checked_at)` — журнал каждой pre-join проверки.
- **geo_policies** `(id, org_id, allowed_countries [array, default ['UZ']], mode [enforce|flag_only|off], block_vpn bool, block_proxy bool, require_gps bool, whitelist_asns [array], whitelist_ips [array])` — политика per-org (или в `organizations.settings` jsonb).
- *(расширение)* **users/sessions:** опц. `last_known_country`, `last_geo_check_at` — кэш/история.

---

## Риски

- **Residential proxy ~70-80%** (из research) — продвинутый VPN через жилые IP детектируется хуже; не 100%.
- **False-positives** (research §5): корп.прокси/CDN/мобильный тетеринг помечаются как VPN → нужен whitelist + flag-режим, иначе блок легитимных пользователей.
- **GPS только mobile** ([D-012]): desktop-фаза без надёжного GPS → гео по IP only (обходится VPN с UZ-exit-нодой без GPS-кросс-чека).
- **GPS-spoofing на rooted** (research §6) — нет идеальной защиты; слоистые проверки снижают, не устраняют.
- **MMDB-актуальность/лицензия:** базы устаревают (daily-update обязателен); лицензия MaxMind — закупка/комплаенс.
- **IP-определение за proxy/балансировщиком:** неверный remote_ip → ложные решения; корректная конфигурация эндпоинта обязательна.

---

## Зависимости

- **E0** (Фундамент) — `audit_logs`, users/sessions, политики per-org.
- **E1** (Ядро конференций) — **pre-join gate встраивается в JWT-выдачу** (`livekitex`); E7 расширяет цепочку join-проверок.
- **mobile-клиент** (фаза 2) — GPS-захват (desktop GPS ненадёжен, [D-012]); до этого — IP-only.
- **MaxMind-лицензия** — закупка GeoIP2 Country + Anonymous IP баз.

---

## Открытые вопросы

1. **Режим по умолчанию:** жёсткий block при VPN/вне-страны, или flag-only + ручное решение Security Officer (минимизация FP на старте)?
2. **Allowed-countries:** только UZ, или есть легитимные удалённые пользователи (командировки/диппредставительства)?
3. **Whitelist:** известны ли корп.прокси/ASN/диапазоны ведомства для исключения из VPN-детекта?
4. **GPS-обязательность:** требовать GPS на mobile принудительно (require_gps), или опционально (privacy/UX)?
5. **Residential proxy:** достаточна ли точность MaxMind ~70-80%, или нужен коммерческий слой (IPQualityScore/Spur on-prem)?
6. **Реакция на flag:** доп.auth (2FA-челлендж) / уведомление Security Officer / запись в журнал — что именно?
7. **Desktop-гео:** приемлемо ли на desktop-фазе только IP-проверка (без GPS-кросс-чека), зная обход через UZ-VPN?
8. **Лицензия MaxMind:** коммерческая закупка одобрена (vs бесплатная GeoLite2 — ниже точность Anonymous IP)?
