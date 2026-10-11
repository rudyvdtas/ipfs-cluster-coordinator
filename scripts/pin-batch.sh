#!/bin/bash
# Generic batch pinning workflow.
#
# Default model:
# - replication min = 2
# - replication max = 3
# - allocation is storage-aware and decided by the cluster allocator
#
# Usage:
#   ./scripts/pin-batch.sh data/batches/week42.json
#   REPL_MIN=3 REPL_MAX=5 ./scripts/pin-batch.sh data/batches/critical.json
#   BATCH_SIZE=20 PAUSE_SECONDS=60 ./scripts/pin-batch.sh data/batches/large.json

set -e

CID_FILE="${1:?Usage: $0 <batch.json>}"
REPL_MIN="${REPL_MIN:-2}"
REPL_MAX="${REPL_MAX:-3}"
BATCH_SIZE="${BATCH_SIZE:-50}"
PAUSE_SECONDS="${PAUSE_SECONDS:-30}"
CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"

if [ ! -f "$CID_FILE" ]; then
  echo "❌ CID file not found: $CID_FILE"
  exit 1
fi

TOTAL=$(python3 -c "import json; print(len(json.load(open('$CID_FILE'))))")

echo "📌 Pinning $(basename "$CID_FILE")"
echo "   Total CIDs: $TOTAL"
echo "   Allocation model: storage-aware cluster allocation"
echo "   Replication: min=$REPL_MIN, max=$REPL_MAX"
echo ""

ALREADY_PINNED=$(${CLUSTER_CTL} --enc json pin ls 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and 'cid' in item:
                print(item['cid'])
    elif isinstance(data, dict) and 'cid' in data:
        print(data['cid'])
except Exception:
    pass
" 2>/dev/null || true)

PINNED=0
SKIPPED=0
ERRORS=0
COUNTER=0

for cid in $(python3 -c "import json; [print(c) for c in json.load(open('$CID_FILE'))]"); do
  COUNTER=$((COUNTER + 1))

  if echo "$ALREADY_PINNED" | grep -qF "$cid"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo -n "[$COUNTER/$TOTAL] $cid ... "
  if ${CLUSTER_CTL} pin add "$cid" \
    --replication-min "$REPL_MIN" \
    --replication-max "$REPL_MAX" \
    >/dev/null 2>&1; then
    echo "✓"
    PINNED=$((PINNED + 1))
  else
    echo "✗"
    ERRORS=$((ERRORS + 1))
  fi

  if [ $((COUNTER % BATCH_SIZE)) -eq 0 ] && [ $COUNTER -lt $TOTAL ]; then
    echo "   ⏸  Pause ${PAUSE_SECONDS}s..."
    sleep "$PAUSE_SECONDS"
  fi
done

echo ""
echo "✅ Done"
echo "   Total:   $TOTAL"
echo "   Pinned:  $PINNED"
echo "   Skipped: $SKIPPED"
echo "   Errors:  $ERRORS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
