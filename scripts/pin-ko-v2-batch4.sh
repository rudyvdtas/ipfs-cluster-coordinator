#!/bin/sh
# Pin KOv2 batch 4 CIDs. Cluster distributes automatically based on freespace.
set -e
CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"
CID_FILE="$1"
[ -f "$CID_FILE" ] || { echo "Usage: bash pin-ko-v2-batch4.sh <csv-file>"; exit 1; }
echo "Pinning KOv2 batch 4 (replication -1)..."
CID_LIST=$(mktemp)
tail -n +2 "$CID_FILE" | cut -d, -f1 | sort -u > "$CID_LIST"
TOTAL=$(wc -l < "$CID_LIST" | tr -d ' ')
ALREADY_PINNED=$(${CLUSTER_CTL} pin ls 2>/dev/null | awk '{print $1}')
PINNED=0; SKIPPED=0; ERRORS=0; C=0
while read cid; do
  C=$((C+1))
  if echo "$ALREADY_PINNED" | grep -qF "$cid"; then SKIPPED=$((SKIPPED+1)); continue; fi
  echo "[${C}/${TOTAL}] ${cid}"
  if ${CLUSTER_CTL} pin add "${cid}" --replication -1 >/dev/null 2>&1; then PINNED=$((PINNED+1)); else echo "  ERROR"; ERRORS=$((ERRORS+1)); fi
done < "$CID_LIST"
rm "$CID_LIST"
echo "--- Done: total=$TOTAL skipped=$SKIPPED pinned=$PINNED errors=$ERRORS"