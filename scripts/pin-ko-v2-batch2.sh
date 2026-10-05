#!/bin/sh
set -e

JOERA_PEERID="12D3KooWEwkft7CBFWzCmNngJRmw42PPQk7dRTaPheWZpV7UHD6g"
VERNIS_PEERID="12D3KooWFnsoGcDhPyRu1vrvTyXzKXgXjBhcNAg3E5p5fVAsnE2o"

CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"
CID_FILE="$(cd "$(dirname "$0")" && pwd)/../curated-cids-ko-v2-batch2.json"

if [ ! -f "$CID_FILE" ]; then
  echo "ERROR: $CID_FILE not found"
  exit 1
fi

echo "Pinning KOv2 batch 2 — exclusively to joera + vernis-artbox"
echo "Replication: min=2, max=2"
echo ""

PINNED=0
SKIPPED=0
ERRORS=0

ALREADY_PINNED=$(${CLUSTER_CTL} --enc json pin ls 2>/dev/null | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    exit()
data = json.loads(raw)
if isinstance(data, list):
    for d in data:
        if 'cid' in d:
            print(d['cid'])
elif isinstance(data, dict) and 'cid' in data:
    print(data['cid'])
" 2>/dev/null || true)

TOTAL=$(python3 -c "import json; print(len(json.load(open('${CID_FILE}'))))")

for cid in $(python3 -c "
import json
for c in json.load(open('${CID_FILE}')):
    print(c)
"); do
  if echo "$ALREADY_PINNED" | grep -qF "$cid"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  echo "Pinning ${cid} (${PINNED}/${TOTAL})..."
  if ${CLUSTER_CTL} pin add "${cid}" \
    --allocations "${JOERA_PEERID},${VERNIS_PEERID}" \
    --replication-min 2 --replication-max 2 \
    >/dev/null 2>&1; then
    PINNED=$((PINNED + 1))
  else
    echo "  ERROR: ${cid}"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "--- Done ---"
echo "Total:       ${TOTAL}"
echo "Skipped:     ${SKIPPED}"
echo "Newly added: ${PINNED}"
echo "Errors:      ${ERRORS}"