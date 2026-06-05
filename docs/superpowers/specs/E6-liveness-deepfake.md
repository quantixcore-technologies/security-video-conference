# E6 — Подтверждение реальности (ML: liveness / анти-DeepFake / face-match)

> **Статус:** план-спек (далёкая фаза; детализируется перед Фазой 7). Greenfield.
> **Источники:** [research/ml-stack.md](../../research/ml-stack.md), ADR [D-011](../../ARCHITECTURE_DECISIONS.md) (Python+Rust гибрид), [D-010](../../ARCHITECTURE_DECISIONS.md) (E2EE off → ML видит кадры), [D-009](../../ARCHITECTURE_DECISIONS.md) (Egress), мастер-план §4 (E6).

---

## ⚠️ Честная рамка (НЕ overpromise)

> Из [ml-stack.md](../../research/ml-stack.md) и [D-011]:
> - **Face-match (1:1)** к фото профиля — **production-grade** (~98% real-world, InsightFace/ArcFace). **Приоритет №1.**
> - **Liveness (PAD)** — production при hybrid passive+active (MiniFASNet + challenge). **Приоритет №2.**
> - **Deepfake-детект** real-time — **research-grade (~78% real-world**, lab 95-99% вводит в заблуждение) → **risk-flag + human review, НЕ автобан. R&D-трек.**
> - **Latency:** полный пайплайн ~300ms best / 500+ms realistic; GPU-память 3 модели ≈ 10-12GB из 16GB.
> - **Возможно благодаря [D-010]:** E2EE **off** → сервер (доверенный, on-prem) видит кадры для ML.

---

## Цель

Подтверждать, что участник конференции — **реальный, живой человек, соответствующий профилю** (Фото/ФИО из E2), а не фото/видео/маска/deepfake. Закрывает пункт ТЗ «проверка активности/реальности (защита от DeepFake)». Интегрируется с посещаемостью (верификация личности присутствующего).

---

## Scope (пункты ТЗ → задачи)

- **Face-match 1:1** (приоритет): кадр участника ↔ фото профиля (E2 enrollment) → similarity-score → verified/mismatch.
- **Liveness / PAD:** passive (MiniFASNet, анти-спуф фото/экрана) + active challenge («моргни», «поверни голову») → live/spoof.
- **Deepfake-детект (R&D):** флаг подозрения на синтетическое видео → **risk-flag**, не reject; накопление для human review.
- **Frame-sourcing:** получение кадров участника server-side через LiveKit (Egress/Agent track-subscription, [D-009]/[D-010]).
- **Интеграция с attendance (E2):** результат верификации → статус «identity_verified» в `attendance_records`, audit.
- **Human-review-флоу:** очередь подозрительных событий (deepfake-флаг/mismatch) для Security Officer.

---

## Ключевые задачи

1. **ML-сервис (отдельный):** Python (FastAPI, модели, препроцессинг) + Rust (`ort`/ONNX Runtime, GPU-инференс) на GPU-ноде (RTX 4060 Ti 16GB). Каталог `ml_service/` (см. мастер-план §9).
2. **Face-match (InsightFace/ArcFace):** ONNX, эмбеддинг кадра ↔ эмбеддинг фото профиля, cosine-similarity, порог; quality-gate (лицо >80px, frontal). **Реализовать первым** (production).
3. **Liveness (MiniFASNet-V2 + temporal):** passive PAD + active-challenge оркестрация (клиент показывает инструкцию, ML проверяет реакцию). Комбинировать против тёмных/масочных кейсов.
4. **Deepfake-детектор (R&D-трек):** open-модель (CrossBranch-Orthogonality / DeepFake-Detect, DFDC-trained), позиционирование risk-flag; **бюджет на ONNX-порт** (ports «half-baked», research velocity в PyTorch).
5. **Frame-sourcing pipeline:** **Pattern B (Trusted agent / Egress track subscription)** — доверенный ML-сервис получает плэйнтекст-кадры в своём silo (sample ~1fps speaking / 0.3fps idle, resize ~1024², JPEG), результаты → audit/attendance.
6. **Phoenix↔ML интеграция:** gRPC/REST (через Finch), асинхронно; результаты → `identity_verifications`/`attendance_records`/`audit_logs`.
7. **GPU-ресурс-менеджмент:** load on-demand, очередь-батчинг (20+ участников), мониторинг VRAM.
8. **Human-review UI** (LiveView, Security Officer): очередь флагов, просмотр кадра/скоров, решение verify/reject/escalate.
9. **Enrollment-связь (E2):** использовать фото профиля как reference; политика повторной верификации (на входе / периодически в встрече).

---

## Технический подход

- **Гибрид Python+Rust** ([D-011], [ml-stack.md]): Python для model-ops/препроцессинга/FastAPI; **Rust (`ort`)** для high-throughput GPU-инференса (p99 850ms→45ms, 10x throughput — research). Чистый Rust нельзя (99% моделей в PyTorch); чистый Python — GIL/GC убивают p99.
- **Модели:** **InsightFace/ArcFace** (face-match, приоритет), **MiniFASNet-V2** (liveness), open deepfake-детектор (R&D). Альтернативы: коммерческие iProov/FaceTec (liveness), Reality Defender (deepfake) — если open недостаточно.
- **GPU-рантайм:** `ort` crate (CUDA/TensorRT, prod-ready); alt `tract` (pure-Rust, незрел). TensorRT-оптимизация (NVIDIA Model-Optimizer) для latency.
- **Frame-sourcing [D-009]/[D-010]:** **Pattern B** (trusted agent) — НЕ client-side attestation (Pattern A не для employer-monitoring, доверяет клиенту). Egress/Agents auto-subscribe → плэйнтекст (E2EE off). Тот же Egress-механизм, что серверная запись E2 ([D-009] последствие).
- **Архитектура:** `Phoenix → ML-сервис (gRPC/REST) → результаты в audit/attendance` (мастер-план §4 E6). ML-сервис в отдельном silo (security-изоляция).
- **Деплой:** GPU-нода K8s (Нода2 — Agents/ML, из [livekit-selfhost-e2ee.md] §1); runbook `docs/runbooks/ml-service-deploy.md`.

---

## Предварительные доменные сущности (Ecto)

> ML-инференс — в `ml_service/` (Python/Rust); Phoenix хранит результаты/очереди/референсы. Все таблицы несут `org_id` ([D-005]).

- **identity_verifications** `(id, org_id, meeting_id, user_id, kind [face_match|liveness|deepfake], result [pass|fail|flag|error], score float, threshold float, model_version, frame_ref?, latency_ms, verified_at)` — результат каждой ML-проверки.
- **face_enrollments** `(id, org_id, user_id, embedding_ref/vector, source_photo_path [из E2-профиля], model_version, enrolled_at, active)` — reference-эмбеддинг профиля для face-match (связь с E2 `users.photo_path`).
- **liveness_challenges** `(id, org_id, meeting_id, user_id, challenge_type [blink|turn|smile], issued_at, responded_at, passed)` — active-challenge сессии.
- **review_queue** `(id, org_id, verification_id, status [pending|reviewed], reviewer_id?, decision [verified|rejected|escalated]?, notes, created_at, reviewed_at)` — human-review подозрительных (deepfake-flag/mismatch).
- *(расширение E2)* **attendance_records:** `+identity_verified bool`, `+verification_id?` — связь посещаемости с верификацией.

---

## Риски

- **Deepfake real-time — research-grade (~78%)** (из research): позиционировать risk-flagging, **НЕ автоматический reject**; lab-бенчмарки (95-99%) вводят в заблуждение. Не продавать как 100% ([D-011] последствие).
- **Liveness падает** в темноте/масках/углах → комбинировать passive+active (обязательно).
- **Face-match деградирует** на плохих кадрах → quality threshold (>80px, frontal) + retry.
- **Latency** 300-500ms полный пайплайн — учесть в UX (верификация на входе, не блокирует поток жёстко).
- **GPU-память** 16GB на 3 модели ≈ 10-12GB → load on-demand, очередь-батчинг на 20+ участников, мониторинг (риск OOM).
- **Rust ML-экосистема незрела** — тестировать ONNX-экспорт в dev, бюджет на порт нишевых deepfake-моделей.
- **Приватность/комплаенс:** биометрия (лица/эмбеддинги) — гос-требования к хранению/согласию (открытый вопрос, связь с compliance.md).

---

## Зависимости

- **E1** (Ядро конференций) — LiveKit-медиа, Egress/Agents для frame-sourcing; **E2EE off** ([D-010]) обязательно.
- **E2** (Посещаемость + Личность) — **фото профиля** (reference для face-match), enrollment, интеграция результата в `attendance_records`.
- **GPU-инфра** — Нода2 K8s (RTX 4060 Ti), деплой ML-сервиса.
- *(инфра-связь)* **E5** — общий media/ML-silo; Egress может нести аудио-watermark.

---

## Открытые вопросы

1. **Когда верифицировать:** только на входе, периодически в течение встречи, или по триггеру (Security Officer запрашивает)?
2. **Реакция на fail/flak:** face-mismatch → block join? liveness-fail → retry-challenge? deepfake-flag → только в review-queue (НЕ автобан — решено)?
3. **Deepfake-трек реально нужен сейчас** (R&D-стоимость, ~78%) или отложить, начав с face-match + liveness (production)?
4. **Биометрия-комплаенс:** гос-требования к хранению эмбеддингов/фото, согласие сотрудников, сроки хранения (→ compliance.md).
5. **Active-challenge UX:** какие челленджи приемлемы (моргнуть/повернуться) без раздражения на каждой встрече?
6. **Коммерческие модели:** бюджет на iProov/FaceTec/Reality Defender, если open-source недостаточен по точности?
7. **Порог similarity** face-match: баланс FAR/FRR для гос (строгий порог → больше ложных отказов)?
8. **Связь с enrollment (E2):** кто и как загружает эталонное фото (HR при заведении сотрудника)? Качество фото-гейт?
