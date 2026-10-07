#!/bin/sh
set -e

ZOMI_PEERID="12D3KooWJinwFX9Cjud73WjAmeh2g4JR789jPR2wKaYHzoSwaQLC"
RUDEBERRY_PEERID="12D3KooWSJPpqQqUpLCTMN91QnpjpXSQPx9ps2kYoJ9cF86Ah3mE"

CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"
CID_FILE="$(cd "$(dirname "$0")" && pwd)/../curated-cids-ko-v2-batch3.json"

if [ ! -f "$CID_FILE" ]; then
  echo "ERROR: $CID_FILE not found"
  exit 1
fi

echo "Pinning KOv2 batch 3 — exclusively to zomi + rudeberry-pi"
echo "Replication: min=2, max=2"
echo ""

PINNED=0
SKIPPED=0
ERRORS=0

ALREADY_PINNED=$(${CLUSTER_CTL} pin ls 2>/dev/null | awk '{print $1}')

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
    --allocations "${ZOMI_PEERID},${RUDEBERRY_PEERID}" \
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