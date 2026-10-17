# Qwen3.8-Flash-Next-FP4-Spark-recipe

Serving recipe for **nvidia/Qwen3.8-Flash-Next-FP4-Local** on a single NVIDIA
DGX Spark (GB10, 128 GB unified memory), using NVIDIA's required b12x serving
container. Every number below was measured on that exact deployment; the flag
set in `scripts/` is the one that produced them.

**Model (Hugging Face):** <https://huggingface.co/nvidia/Qwen3.8-Flash-Next-FP4-Local>

The upstream vLLM build cannot read this checkpoint's NVFP4+csf expert scales;
the b12x container is mandatory. Follow the model card's environment block
verbatim, then apply the two measured overrides documented here
(`B12X_AUTOTUNE=0`, `B12X_COMPILE_WORKERS=1`).

## Status

| Deployment | Folder | Model | Engine | Status |
|---|---|---|---|---|
| 1x Spark, TP1/PP1 | `scripts/` | nvidia/Qwen3.8-Flash-Next-FP4-Local | eugr/spark-vllm-b12x (digest-pinned) + vLLM MTP speculative decode | **Measured, serving** |

## Quick start (one Spark)

```bash
export HF_TOKEN=<your token>          # must already have access to the model repo
bash scripts/download_and_verify.sh  # hf_xet download + pinned-manifest sha256 verify
bash scripts/serve.sh               # launches the b12x container detached
bash scripts/guard.sh status         # container + endpoint + memory snapshot
bash scripts/smoke.sh                # native completion check, must finish_reason=stop
```

The API is OpenAI-compatible at `http://<host>:8000/v1`. Clients that append
`/chat/completions` themselves must be given the base URL **including** `/v1`.

## The measured flag set (do not deviate without re-measuring)

Two overrides over the model card's environment block, both verified in the
shipped runtime source before use:

- `B12X_AUTOTUNE=0` — skips the optional per-kernel autotune sweep. With tuning
  enabled, the sweep walks ~690 kernels across four groups; the measured pace
  at one compile worker was ~1.6 min/kernel, i.e. **hours** of bring-up. With
  the flag set, all four groups resolve from prebuilt artifacts in ~70 s with
  zero compilations and total time-to-API is **5:16**. The equivalent
  interactive path is the startup prompt's "Press ESC to use default tuning".
- `B12X_COMPILE_WORKERS=1` — the 4-worker default OOMs a 128 GB Spark during
  the compile burst (measured: 22.5 to 8 GiB available in 60 s). One worker
  compiles serialized and fits.

Everything else is the model card's block, including the PLE n-gram table
offload (`VLLM_PLE_TABLE_MEMORY=disk`, `B12X_DISK_BACKEND=io_uring`): the
~26 GB packed n-gram table is paged directly from the on-disk checkpoint via
io_uring and never routes to device memory. Loader arithmetic:
102.26 GB repo minus 71.74 GB main weights minus 4.14 GB MTP draft = 26.38 GB
never routed to the device.

## Measured bring-up (single Spark, digest-pinned container)

| Phase | Measured |
|---|---|
| Weight shards routed (21/21, 71.74 GB) | 2:06 |
| MTP draft (4.14 GB) | +8 s (weight phase total 3:13) |
| Kernel preparation, all 4 groups, zero compilations | ~70 s |
| Engine init | 78.6 s |
| **API ready (total)** | **5:16** |
| First successful completion | 5:44 |

Container image: `eugr/spark-vllm-b12x:latest`, digest
`sha256:03a956544e9f9b4b7ba91690469fbe7848bdbef29a7d2e0f5788368467bb3595`.
Serve with that digest pinned (see `scripts/serve.sh`).

## Measured memory (128 GB unified)

| Metric | Value |
|---|---|
| Engine reservation | 97.35 GiB |
| Steady-state MemAvailable | ~20 GiB |
| Load-window swap spike | +3.2 GiB, one-time, self-healing (see note) |
| n-gram PLE table | 26.38 GB paged from NVMe, not resident |

Load-window note: available memory dips and swap grows once during weight
loading even with tuning disabled. In the measured run swap stayed flat after
the spike and self-healed to +2.58 GiB; the box never became unstable. The
memory guard stayed armed throughout and the spike is disclosed, not hidden.
Residual swap (~2.7 GiB) clears only on a serve stop. **Keep the guard
armed**: 2 GiB MemAvailable floor, 16 MiB swap-growth tolerance, 60 s poll
(`scripts/guard.sh`).

## Measured speed (client-observed; this route exposes no server metrics)

All figures from an unscored synthetic speed suite at the measured
concurrency; p99 values come from 32 samples (weak tail evidence). The three
workload aggregates are not comparable to each other.

| Workload | Measured |
|---|---|
| Single-stream decode (C=1 p50) | 68.06 tok/s |
| Decode aggregate knee | 136.44 tok/s at C=8 (per-stream p50 7.52 / p90 15.16 tok/s) |
| Balanced aggregate | 119.90 tok/s at C=8, TTFT p95 1877 ms |
| Single-stream prefill (C=1 p50) | 1718.76 tok/s |

Concurrent decode crushes each stream ~4.5x while aggregate only ~2x; do not
read the C=8 aggregate as a per-user rate. MTP speculative decode is active
(num_speculative_tokens=4); its acceptance rate was **not measured**, so the
single-stream figure cannot be decomposed into accepted vs rejected rounds.

## Measured quality (private qualification runs, not leaderboard scores)

Six-category suite, 120 items, all categories including locally executed
code, thinking on. Two separate receipts, never merged:

| Policy | Score | Scope | Caveats |
|---|---|---|---|
| Deterministic (temp 0) | 89.9 | 107/119 | 1 benchmark-defective item unanswerable at temp 0; 2 budget-exhaustion truncations |
| Vendor (temp 1.0, top_p 0.95, top_k 20) | 90.8 | 109/120 | zero truncations; complete scope |

Per-category (vendor receipt): knowledge 90.0, math 100.0, truth 80.0,
instruct 95.0, code 95.0, tools 85.0. Eight items fail under both policies.
The vendor measurement is the cleaner one: temp-1.0 sampling breaks the
deterministic reasoning loops that burned entire token budgets at temp 0.
Neither score is comparable to a public leaderboard or to an untruncated run.

## What is NOT attributed

- MTP acceptance rate: unmeasured. Any speed decomposition into
  accepted/rejected speculative rounds is unproven.
- Server-side prefill/decode/queue metrics: this route does not expose them;
  every speed number above is client-observed.
- The 2 budget-exhaustion failures in the temp-0 receipt are artifacts of
  this box's throughput, not clean capability measurements.
- Anything outside the exact container digest, flag set, and 128 GB GB10
  host class above is unverified.

## Cards tested on

| Card | VRAM | Status |
|---|---|---|
| NVIDIA DGX Spark (GB10) | 128 GB unified | Measured (this recipe) |

Nothing else has been verified. The recipe needs roughly 98 GB of device
reservation plus headroom; smaller unified-memory parts are untested.

## Fidelity context

Weight-space damage of the NVFP4+csf quantization was measured directly
against the BF16 teacher checkpoint: relative error 0.0961 +/- 0.0004,
cosine 0.9954, per-row top-1 agreement 0.778 across all depths, experts, and
projections, uniform by design (QAD distillation equalized the error; no
hotspots). The decode chain was validated bitwise against the container's
own reference dequantizer. These are weight-space figures, not quality
scores; the quality scores above are the measured behavioral figures.

## Credits and license

- Model and serving procedure: NVIDIA's model card at the HF repo linked
  above. The two overrides here are measured additions, both verified against
  the shipped runtime source before use.
- Recipe scripts: MIT.

## Repo layout

| Path | What |
|---|---|
| `scripts/download_and_verify.sh` | hf_xet high-performance download + pinned-manifest sha256 verification |
| `scripts/serve.sh` | host wrapper: digest-pinned b12x container, detached |
| `scripts/serve_inner.sh` | the exact measured in-container environment block + vLLM invocation |
| `scripts/guard.sh` | memory guard + status watcher (2 GiB floor, 16 MiB swap tolerance) |
| `scripts/smoke.sh` | native completion verification |
