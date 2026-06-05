# Разведка: LiveKit self-host + E2EE + Net/Geo (E1, E7)

> Источник: research-отряд №3. Контекст: B2G, on-prem K8s, серверный ML на кадрах.

## 1. LiveKit self-host на Kubernetes
- **Helm-чарт** ([livekit-helm](https://github.com/livekit/livekit-helm)): `livekit-server` (SFU), **Redis** (multi-node coord), **coTURN**, Ingress.
- **Networking-гочи:** host-networking обязателен (RTC UDP/TCP порты биндятся прямо на ноду, без kube-proxy/NAT) → **1 LiveKit pod на физическую ноду**. UDP LoadBalancer сложнее TCP. Приватные/serverless кластеры не поддерживаются (NAT ломает WebRTC).
- **Сайзинг агентов (ML):** CPU 500m-1000m, Mem 512Mi-1Gi, ephemeral 10GB, HPA 70% CPU. `terminationGracePeriodSeconds: 18000` (дренаж сессий).
- **2-node форма:** Нода1 — LiveKit Server + Redis + coTURN; Нода2 — Agents (ML) + Egress; внешне — LoadBalancer/HAProxy + S3-совместимое хранилище.

## 2. E2EE vs серверный ML — КЛЮЧЕВОЕ ПРОТИВОРЕЧИЕ
- LiveKit **E2EE** (insertable streams) шифрует медиа ключом, известным только участникам — SFU видит «opaque bytes», **не может декодировать**.
- LiveKit **Agents не умеют декодировать E2EE-треки** → deepfake/liveness ML невозможен. **Egress несовместим с E2EE.**
- **Вердикт для employer-monitoring: ВЫКЛЮЧИТЬ E2EE.** Использовать **hop-by-hop DTLS-SRTP** (SFU декодирует in-memory, доверенная точка) + **at-rest AES-256** + **TLS** для сигналинга/API/webhooks. Компания доверяет своим серверам; on-prem аудит.
- **Кадры к ML:** Agents auto-subscribe (sample 1fps speaking / 0.3fps idle, resize 1024², JPEG) ИЛИ Track Egress → S3 → batch ML.

## 3. Elixir/Phoenix интеграция (ПОДТВЕРЖДЕНО)
- Hex SDK: **`livekit`** (~60-70% API) и **`livekitex`** (полнее, активный).
- **JWT (HS256):** `AccessToken.new(key, secret) |> with_identity |> with_grants(join_room) |> to_jwt`. Симметричный ключ, без асимметрии.
- **RoomService REST/Twirp:** через **Finch** (рекоменд.) — CreateRoom, ListRooms, RemoveParticipant, ListParticipants (`/twirp/livekit.RoomService/*`).
- **Webhooks:** POST с JWT (SHA256 HMAC тела) в `Authorization`. События `room_started`, `participant_joined/left`, `track_published`. **Читать raw body ДО Plug-парсинга.** → журнал посещаемости в Postgres.

## 4. Контроль записи (нюанс)
Запись и ML используют **тот же Egress-механизм**. `room_record` grant. Запись server-initiated (участник не блокирует). Нет granular RBAC «писать комнату, но не участника». **Для «no recording»:** отключать Egress на уровне бизнес-логики (`recording_disabled: true` → reject Egress). ML-доступ к кадрам = тот же Egress (нельзя разделить на уровне LiveKit).

## 5. VPN/proxy-детект — self-hostable
- **MaxMind GeoIP2 Anonymous IP** ([db](https://www.maxmind.com/en/geoip-anonymous-ip-database)) + Elixir **`locus`** ([hex](https://hexdocs.pm/locus/)) — читает MMDB локально, **без внешних API**. Идеально под «Max Data Security Private».
- Точность: VPN-провайдеры 95%+, residential proxy ~70-80% (сложнее), false-positives (корп.прокси/CDN/тетеринг). Обновление daily.
- Commercial (лучше residential): IPQualityScore, Spur (есть on-prem), MaxMind Anonymous Plus.

## 6. Гео-блок (IP + GPS кросс-чек)
- MaxMind GeoIP2 Country (self-host через Locus) → country_from_ip.
- Device GPS (`navigator.geolocation` / mobile) → lat/lon → country.
- Валидация: ip_country ∉ allowed → block; gps_country ≠ ip_country → flag (VPN+GPS-spoof или поездка) → доп.auth. Spoofing-детект: ASN/datacenter + GPS-континент mismatch. GPS-spoof на rooted — нет идеальной защиты, слоистые проверки.

## Encryption posture (итог)
- E2EE: ❌ off (несовместимо с ML). In-transit: ✅ DTLS-SRTP (hop-by-hop). At-rest: ✅ AES-256 (Egress). Control: ✅ TLS 1.2+.

## Источники
- https://docs.livekit.io/transport/self-hosting/kubernetes/ · https://github.com/livekit/livekit-helm
- https://livekit.com/security/overview · https://docs.livekit.io/home/client/tracks/encryption/
- https://docs.livekit.io/agents/ · https://docs.livekit.io/home/egress/overview/
- https://docs.livekit.io/intro/basics/rooms-participants-tracks/webhooks-events/
- https://hexdocs.pm/livekit/ · https://hexdocs.pm/livekitex/
- https://github.com/g-andrade/locus · https://www.maxmind.com/en/geoip-anonymous-ip-database
- https://antmedia.io/webrtc-security/ · https://aws.amazon.com/blogs/containers/how-to-route-udp-traffic-into-kubernetes/
- https://github.com/sneako/finch · https://www.guardsquare.com/blog/securing-location-trust-to-prevent-geo-spoofing
