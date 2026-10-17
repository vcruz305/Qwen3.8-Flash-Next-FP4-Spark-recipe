#!/bin/bash
# In-container serve script for nvidia/Qwen3.8-Flash-Next-FP4-Local.
# This is the exact measured environment block (HF model card) plus the two
# measured overrides (B12X_AUTOTUNE=0, B12X_COMPILE_WORKERS=1).
export VLLM_PLE_TABLE_MEMORY="disk"
export B12X_DISK_BACKEND="io_uring"
export CUTE_DSL_ARCH="sm_121a"
export SAFETENSORS_FAST_GPU="1"
export VLLM_WORKER_MULTIPROC_METHOD="spawn"
export VLLM_SSM_CONV_STATE_LAYOUT="DS"
export VLLM_USE_AOT_COMPILE="1"
export VLLM_USE_MEGA_AOT_ARTIFACT="1"
export VLLM_USE_V2_MODEL_RUNNER="1"
export B12X_POLICY_MODE="auto"
export VLLM_MXFP8_LM_HEAD="1"
export VLLM_B12X_MOE_FP4_LAYER_MAX_INPUT_SCALE="w13"
export VLLM_B12X_MOE_FP4_FORCE_A16=1
export B12X_W4A16_A4_PREFILL=1
export B12X_COMPILE_WORKERS=1
export B12X_AUTOTUNE=0
exec vllm serve nvidia/Qwen3.8-Flash-Next-FP4-Local \
    --host 0.0.0.0 \
    --port 8000 \
    --tensor-parallel-size 1 \
    --pipeline-parallel-size 1 \
    --mamba-cache-mode align \
    --enable-prefix-caching \
    --enable-chunked-prefill \
    --dtype bfloat16 \
    --kv-cache-dtype fp8 \
    --quantization modelopt_mixed \
    --block-size 16 \
    --load-format b12x \
    --max-model-len 262144 \
    --max-num-seqs 8 \
    --max-num-batched-tokens 4096 \
    --speculative-config '{"method":"mtp","num_speculative_tokens":4}' \
    --gdn-decode-kernel b12x \
    --linear-backend b12x \
    --moe-backend b12x \
    --no-enable-flashinfer-autotune \
    --mm-encoder-tp-mode data \
    --reasoning-parser qwen3 \
    --tool-call-parser qwen3_xml \
    --enable-auto-tool-choice \
    --compilation-config '{"pass_config":{"fuse_act_quant":true}}' \
    --gpu-memory-utilization 0.8
