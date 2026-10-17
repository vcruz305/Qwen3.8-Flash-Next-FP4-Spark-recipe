#!/bin/bash
# Download nvidia/Qwen3.8-Flash-Next-FP4-Local with hf_xet high performance,
# then verify every file against the pinned Hub manifest:
#   - LFS files: sha256(content) == manifest lfs.oid
#   - non-LFS files: byte-for-byte equality with the manifest blob
# Aborts on any mismatch. Never prints the HF token.
set -euo pipefail
MODEL=nvidia/Qwen3.8-Flash-Next-FP4-Local
: "${HF_TOKEN:?Set HF_TOKEN to a token with access to $MODEL}"

export HF_XET_HIGH_PERFORMANCE=1
export HF_HUB_ENABLE_HF_TRANSFER=0   # xet path, not the legacy transfer

python3 - "$MODEL" <<'PY'
import json, os, sys, hashlib, urllib.request

model = sys.argv[1]
token = os.environ["HF_TOKEN"]
api = urllib.request.Request(
    f"https://huggingface.co/api/models/{model}/tree/main?recursive=true",
    headers={"Authorization": f"Bearer {token}"},
)
entries = json.load(urllib.request.urlopen(api))
entries = [e for e in entries if e["type"] == "file"]
print(f"pinned manifest: {len(entries)} files")

# Download through the hub library (xet high performance is inherited from env).
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=model,
    token=token,
    max_workers=2,            # measured: >2 workers causes swap growth on 128 GB UMA
    etag_timeout=60,
)

# Locate the downloaded snapshot.
from huggingface_hub import scan_cache_dir
snap = None
for repo in scan_cache_dir().repos:
    if repo.repo_id == model:
        snap = max(repo.revisions, key=lambda r: r.commit_hash).snapshot_path
if snap is None:
    print("VERIFY FAIL: snapshot not found after download"); sys.exit(1)
print(f"snapshot: {snap}")

lfs_ok = plain_ok = 0
lfs_fail = plain_fail = []
total = 0
for e in entries:
    path = os.path.join(snap, e["path"])
    size = os.path.getsize(path)
    total += size
    lfs = e.get("lfs")
    if lfs:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 22), b""):
                h.update(chunk)
        if h.hexdigest() == lfs["oid"]:
            lfs_ok += 1
        else:
            lfs_fail.append(e["path"])
    else:
        raw = urllib.request.urlopen(urllib.request.Request(
            f"https://huggingface.co/{model}/raw/main/{e['path']}",
            headers={"Authorization": f"Bearer {token}"},
        )).read()
        with open(path, "rb") as fh:
            if fh.read() == raw:
                plain_ok += 1
            else:
                plain_fail.append(e["path"])

print(f"LFS sha256 verified: {lfs_ok}/{sum(1 for e in entries if e.get('lfs'))}")
print(f"non-LFS byte-verified: {plain_ok}/{sum(1 for e in entries if not e.get('lfs'))}")
print(f"total bytes on disk: {total}")
if lfs_fail or plain_fail:
    print("VERIFY FAIL:", lfs_fail + plain_fail); sys.exit(1)
print("VERIFY PASS: every file matches the pinned manifest")
PY
