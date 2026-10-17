#!/bin/bash
# Memory guard and status watcher for the b12x serve.
# Modes: status | watch
#   status: one snapshot (container, endpoint, memory, log tail).
#   watch:  polls until the endpoint answers, the container dies, the memory
#          floor trips, or timeout. The floor is NOT optional: a serve without
#          this guard armed is out of policy.
# Floors: MemAvailable >= 2 GiB; swap growth <= 16 MiB over baseline; 60 s poll.
set -uo pipefail
MODE="${1:-status}"
CONTAINER="${CONTAINER:-qwen38fp4-b12x}"
API_PORT="${API_PORT:-8000}"
MEM_FLOOR_KB=$((2*1048576))
SWAP_TOL_KB=16384
POLL_S=60
MAX_MIN="${MAX_MIN:-360}"

swap_base=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print t-f}' /proc/meminfo)

status_snapshot() {
  echo "date: $(date -Is)"
  echo "container: $(sudo -n docker ps -a --filter "name=$CONTAINER" --format '{{.Status}}' | head -1)"
  echo "endpoint: $(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${API_PORT}/v1/models" 2>/dev/null)"
  awk '/MemAvailable/{printf "mem_available_gib: %.1f\n", $2/1048576} /SwapTotal{t=$2} /SwapFree{f=$2} END{printf "swap_used_kib: %d\n", t-f}' /proc/meminfo
  echo "log_tail:"
  sudo -n docker logs --tail 4 "$CONTAINER" 2>&1 | cut -c1-160
}

if [ "$MODE" = status ]; then status_snapshot; exit 0; fi

start=$(date +%s)
while :; do
  now=$(date +%s); elapsed=$(( (now-start)/60 ))
  if [ "$elapsed" -ge "$MAX_MIN" ]; then echo "MILESTONE=TIMEOUT after ${elapsed}min"; status_snapshot; exit 0; fi

  st=$(sudo -n docker ps -a --filter "name=$CONTAINER" --format '{{.Status}}' | head -1)
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${API_PORT}/v1/models" 2>/dev/null)
  if [ "$code" = 200 ]; then
    echo "MILESTONE=SERVE_UP after ${elapsed}min"
    status_snapshot
    exit 0
  fi
  case "$st" in
    *Exited*|*Dead*) echo "MILESTONE=SERVE_DEAD after ${elapsed}min"; status_snapshot; exit 0 ;;
  esac

  avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  swap_kb=$(awk '/SwapTotal{t=$2} /SwapFree{f=$2} END{print t-f}' /proc/meminfo)
  if [ "$avail_kb" -lt "$MEM_FLOOR_KB" ] || [ $((swap_kb-swap_base)) -gt "$SWAP_TOL_KB" ]; then
    echo "MILESTONE=MEM_GUARD after ${elapsed}min avail_kb=$avail_kb swap_kb=$swap_kb base=$swap_base"
    echo "ACTION: stop the container (sudo -n docker rm -f $CONTAINER) and investigate before any relaunch."
    status_snapshot
    exit 0
  fi
  sleep "$POLL_S"
done
