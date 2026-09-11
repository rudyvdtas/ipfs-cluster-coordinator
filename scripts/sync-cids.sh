#!/bin/sh
# Sync the curated CID list into the cluster.
# Reads curated-cids.json and pins any CID not yet in the pinset.
# Run after the coordinator cluster is running:
#   docker exec cluster ipfs-cluster-ctl pin ls  # check current pins
#   ./scripts/sync-cids.sh
#   docker exec cluster ipfs-cluster-ctl status  # verify
set -e

CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"
REPLICA_MIN="${1:-1}"
REPLICA_MAX="${2:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CID_FILE="${SCRIPT_DIR}/../curated-cids.json"

if [ ! -f "$CID_FILE" ]; then
  echo "curated-cids.json not found at ${CID_FILE}"
  exit 1
fi

echo "Reading curated CID list from ${CID_FILE}..."
echo "Replication: min=${REPLICA_MIN}, max=${REPLICA_MAX}"
echo ""

# Get currently pinned CIDs from the cluster
ALREADY_PINNED=$(${CLUSTER_CTL} --enc json pin ls 2>/dev/null | python3 -c "
import sys, json
if not sys.stdin.read().strip():
  exit()
stdin.seek(0)
data = json.loads(stdin.read())
if isinstance(data, list):
  print('\n'.join(d['cid'] for d in data if 'cid' in d))
elif isinstance(data, dict) and 'cid' in data:
  print(data['cid'])
" 2>/dev/null || true)

TOTAL=$(python3 -c "
import json
with open('${CID_FILE}') as f:
    cids = json.load(f)
print(len(cids))
")

PINNED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

for cid in $(python3 -c "
import json
with open('${CID_FILE}') as f:
    cids = json.load(f)
for c in cids:
    print(c)
"); do
  if echo "$ALREADY_PINNED" | grep -qF "$cid"; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi
  echo "Pinning ${cid} (replica ${REPLICA_MIN}/${REPLICA_MAX})..."
  if ${CLUSTER_CTL} pin add "${cid}" \
    --replication-min "${REPLICA_MIN}" \
    --replication-max "${REPLICA_MAX}" \
    >/dev/null 2>&1; then
    PINNED_COUNT=$((PINNED_COUNT + 1))
  else
    echo "  ERROR: failed to pin ${cid}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
done

echo ""
echo "--- Sync complete ---"
echo "Total in curated list: ${TOTAL}"
echo "Already pinned:        ${SKIPPED_COUNT}"
echo "Newly pinned:          ${PINNED_COUNT}"
echo "Errors:                ${ERROR_COUNT}"