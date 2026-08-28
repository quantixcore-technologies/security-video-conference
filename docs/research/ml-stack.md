# Разведка: ML-стек для E6 (анти-DeepFake / liveness / face-match)

> Источник: research-отряд №1 (web-разведка). Контекст: B2G, self-host, GPU RTX 4060 Ti 16GB.
> Вопрос: язык ML-слоя — Rust vs Python?

## Итоговая рекомендация: Python + Rust ГИБРИД

| Аспект | Решение |
|--------|---------|
| Язык/рантайм | **Python (FastAPI, модели/препроцессинг) + Rust (`ort`/ONNX Runtime, GPU-инференс)**. Чистый Rust нельзя — 99% моделей в PyTorch |
| Deepfake-детект | Open: CrossBranch-Orthogonality / DeepFake-Detect (DFDC-trained). **Real-world ~78%** → risk-flag + human review, НЕ автобан. Commercial: Reality Defender |
| Liveness (PAD) | Open: **MiniFASNet-V2** (Silent-Face-Anti-Spoofing) + temporal. Commercial: iProov/FaceTec. Hybrid passive+active |
| Face-match (1:1) | **InsightFace (ArcFace)** — 99.7% lab / ~98% real-world, ONNX, GPU. Приоритет (production-grade) |
| GPU-рантайм | `ort` crate (ONNX Runtime Rust bindings, prod-ready, CUDA/TensorRT). Alt: `tract` (pure-Rust) |
| Frame-sourcing | **Trusted agent / track subscription (Pattern B)** — server-side ML, E2EE off, employer-trust |

## Почему гибрид
- **Не чистый Rust:** 99% face-recognition/deepfake/liveness моделей тренируются и экспортируются из PyTorch/TF. ONNX-порты нишевых deepfake-детекторов «half-baked». Research velocity — новые статьи дают PyTorch-веса, не ONNX.
- **Не чистый Python:** GIL + per-request overhead (~5-15ms) + GC-паузы убивают p99-latency (цель <100ms для live-video). Потолок ~50-100 req/s; Rust 500+.
- **Гибрид:** Python для model ops/препроцессинга/FastAPI; Rust (`ort`) для high-throughput GPU-инференса. Документировано 10x throughput, p99 850ms→45ms.

## Латентность/точность на RTX 4060 Ti (честно)
- Face-match: 40-60ms/image, ~98%. Liveness: <20ms. Deepfake: 200-400ms/frame, **~78% real-world** (lab 95-99% вводит в заблуждение).
- Полный пайплайн (3 проверки): ~300ms best, 500+ms realistic.
- GPU-память: 3 модели + батчинг ≈ 10-12GB из 16GB. На 20+ участников — очередь/батчинг.

## Frame-sourcing (LiveKit + E2EE)
- **(A)** Client-side + signed attestation — privacy-max, но доверяет клиенту (НЕ для employer-monitoring).
- **(B) Trusted agent / Egress track subscription — РЕКОМЕНД.** Доверенный ML-сервис получает плэйнтекст-кадры в своём silo, пишет результаты в audit. Совместимо с employer-trust.
- **(C)** Hop-by-hop — SFU видит кадры, но нарушает E2EE-премис.

## Честные риски (не overpromise)
1. Real-time deepfake — research-grade (~78% real). Позиционировать как risk-flagging, НЕ автоматический reject.
2. Liveness падает в темноте/масках/углах → комбинировать passive (MiniFASNet) + active (challenge «моргни 3 раза»).
3. Face-match деградирует на плохих кадрах → quality threshold (face >80px, frontal), retry.
4. Rust model ecosystem незрел — тестировать ONNX-экспорт в dev, бюджет на порт.
5. GPU-память 16GB — load on-demand, очередь-батчинг, мониторинг.

## Источники
- https://ort.pyke.io/ (ONNX Runtime Rust)
- https://github.com/aaronchong888/DeepFake-Detect
- https://www.realitydefender.com/insights/lab-benchmarks-ineffective-in-deepfake-detection
- https://dev.to/wintrover/upgrading-face-recognition-from-deepface-to-insightface-performance-quality-and-integration-5b7f
- https://github.com/minivision-ai/Silent-Face-Anti-Spoofing (MiniFASNet)
- https://github.com/sonos/tract
- https://github.com/NVIDIA/Model-Optimizer (TensorRT)
- https://github.com/triton-inference-server/pytriton
- https://docs.livekit.io/transport/media/ingress-egress/egress/
- https://www.iproov.com/liveness-detection
- https://www.ijraset.com/research-paper/real-time-deepfake-detection
