#!/bin/bash
# Host wrapper: launch the digest-pinned b12x container serving
# nvidia/Qwen3.8-Flash-Next-FP4-Local on ONE Spark. Detached, unattended.
#
# Requires: passwordless docker (sudo -n), HF_TOKEN with access to the model,
# the model already downloaded and verified (download_and_verify.sh), and
# serve_inner.sh present at $INNER (default ~/serve_inner.sh).
set -euo pipefail

: "${HF_TOKEN:?Set HF_TOKEN to a token with access to nvidia/Qwen3.8-Flash-Next-FP4-Local}"
INNER="${INNER:-$HOME/serve_inner.sh}"
[ -f "$INNER" ] || { echo "serve_inner.sh not found at $INNER (set INNER=)"; exit 1; }

CONTAINER=qwen38fp4-b12x
IMAGE=eugr/spark-vllm-b12x:latest@sha256:03a956544e9f9b4b7ba91690469fbe7848bdbef29a7d2e0f5788368467bb3595

mkdir -p "$HOME/.cache/huggingface" "$HOME/.cache/vllm" "$HOME/.cache/flashinfer" "$HOME/.triton" "$HOME/.cache/b12x"

sudo -n docker rm -f "$CONTAINER" 2>/dev/null || true

sudo -n docker run -d \
  --name "$CONTAINER" \
  --init \
  --gpus all \
  --ipc host \
  --network host \
  --shm-size=16g \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --restart unless-stopped \
  --stop-timeout 120 \
  -e HF_TOKEN="$HF_TOKEN" \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  -v "$HOME/.cache/vllm:/root/.cache/vllm" \
  -v "$HOME/.cache/flashinfer:/root/.cache/flashinfer" \
  -v "$HOME/.triton:/root/.triton" \
  -v "$HOME/.cache/b12x:/root/.cache/b12x" \
  -v "$INNER:/root/serve.sh:ro" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  /root/serve.sh

echo "LAUNCHED container=$CONTAINER (image digest-pinned)"
sudo -n docker ps --filter "name=$CONTAINER" --format '{{.Names}} {{.Status}}'
echo "Arm the guard: bash scripts/guard.sh watch"
