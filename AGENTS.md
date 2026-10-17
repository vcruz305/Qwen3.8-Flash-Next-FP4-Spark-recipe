# Qwen3.8-Flash-Next-FP4 serving recipe (single Spark)

Serve nvidia/Qwen3.8-Flash-Next-FP4-Local on ONE NVIDIA DGX Spark using the
mandatory b12x container. Read the README first: the measured flag set and the
memory guard policy are not optional.

Do NOT:
- install or use upstream vLLM directly for this checkpoint (cannot read
  NVFP4+csf expert scales; the b12x container is mandatory)
- enable the autotune sweep (B12X_AUTOTUNE unset or =1): hours of bring-up
  instead of ~5 minutes
- raise B12X_COMPILE_WORKERS above 1: OOMs a 128 GB Spark during compile
- run without scripts/guard.sh armed (2 GiB floor, 16 MiB swap tolerance)
- print or commit HF tokens anywhere

Exact commands: see README "Quick start".
