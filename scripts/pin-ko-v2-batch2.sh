#!/bin/sh
# Pin KOv2 batch 2 CIDs. Cluster distributes automatically based on freespace.
# Standard model: replication min=2, max=3 — allocator picks peers with most free space.
set -e

CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"
CID_FILE="$(cd "$(dirname "$0")" && pwd)/../curated-cids-ko-v2-batch2.json"

if [ ! -f "$CID_FILE" ]; then
  echo "ERROR: $CID_FILE not found"
  exit 1
fi

echo "Pinning KOv2 batch 2 (replication min=2, max=3)..."
ALREADY_PINNED=$(${CLUSTER_CTL} pin ls 2>/dev/null | awk '{print $1}')
TOTAL=$(python3 -c "import json; print(len(json.load(open('${CID_FILE}'))))")

PINNED=0
SKIPPED=0
ERRORS=0
C=0

for cid in $(python3 -c "import json; [print(c) for c in json.load(open('${CID_FILE}'))]"); do
  C=$((C + 1))
  if echo "$ALREADY_PINNED" | grep -qF "$cid"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  echo "[${C}/${TOTAL}] ${cid}"
  if ${CLUSTER_CTL} pin add "${cid}" \
    --replication-min 2 --replication-max 3 \
    >/dev/null 2>&1; then
    PINNED=$((PINNED + 1))
  else
    echo "  ERROR"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "--- Done ---"
echo "Total:       ${TOTAL}"
echo "Skipped:     ${SKIPPED}"
echo "Newly added: ${PINNED}"
echo "Errors:      ${ERRORS}"
