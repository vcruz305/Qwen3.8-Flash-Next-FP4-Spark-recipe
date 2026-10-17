#!/bin/bash
# Native completion verification: the serve is only "up" if a fresh request
# returns the exact requested output with finish_reason=stop.
set -euo pipefail
API_PORT="${API_PORT:-8000}"
BASE="http://127.0.0.1:${API_PORT}/v1"
MODEL=nvidia/Qwen3.8-Flash-Next-FP4-Local

RESP=$(curl -s -m 120 "$BASE/chat/completions" -H 'Content-Type: application/json' -d '{
  "model": "'"$MODEL"'",
  "messages": [{"role": "user", "content": "Reply with exactly the two characters: OK"}],
  "max_tokens": 500,
  "temperature": 0,
  "chat_template_kwargs": {"enable_thinking": false}
}')

python3 - "$RESP" <<'PY'
import json, sys
try:
    r = json.loads(sys.argv[1])
except Exception as e:
    print("SMOKE FAIL: unparseable response:", e); sys.exit(1)
try:
    msg = r["choices"][0]["message"]
    finish = r["choices"][0]["finish_reason"]
except Exception as e:
    print("SMOKE FAIL: no completion in response:", e); sys.exit(1)
content = (msg.get("content") or "").strip()
if finish == "stop" and content == "OK":
    print("SMOKE PASS: exact output, finish_reason=stop")
    sys.exit(0)
print(f"SMOKE FAIL: finish_reason={finish!r} content={content[:80]!r}")
sys.exit(1)
PY
