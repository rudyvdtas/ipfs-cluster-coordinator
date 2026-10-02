#!/bin/sh
# Rebalance the curated CID list across all available peers.
# Run after every new volunteer joins to redistribute CIDs.
# Target replication: min=3, max=3 (or less when fewer peers are online).
set -e

CN=$(docker ps --format '{{.Names}}' | grep -v tracker | grep cluster | head -1)
[ -z "$CN" ] && { echo "Cluster container not found."; exit 1; }

CLUSTER_CTL="docker exec $CN ipfs-cluster-ctl"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CID_FILE="${SCRIPT_DIR}/../curated-cids.json"

PEER_COUNT=$(${CLUSTER_CTL} id 2>/dev/null | sed -n 's/.*Sees \([0-9]*\) other peers.*/\1/p' || echo 0)
PEER_COUNT=$((PEER_COUNT + 1))  # +1 voor zichzelf

TARGET=$(python3 -c "print(min(3, ${PEER_COUNT}))")

echo "Peers in cluster: ${PEER_COUNT}"
echo "Target replication: min=${TARGET}, max=${TARGET}"
echo ""

if [ "$TARGET" -lt 2 ]; then
  echo "Need at least 2 peers. Only ${PEER_COUNT} peer(s) available. Skipping."
  exit 0
fi

TOTAL=$(python3 -c "import json; print(len(json.load(open('${CID_FILE}', 'r'))))" 2>/dev/null || echo 0)
echo "Rebalancing ${TOTAL} CIDs to replication=${TARGET}..."
echo ""

COUNTER=0
ERRORS=0

for cid in $(python3 -c "
import json
for c in json.load(open('${CID_FILE}', 'r')): print(c)
" 2>/dev/null); do
  COUNTER=$((COUNTER + 1))
  echo -n "[${COUNTER}/${TOTAL}] ${cid} ... "
  if ${CLUSTER_CTL} pin add "${cid}" \
    --replication-min "${TARGET}" \
    --replication-max "${TARGET}" \
    >/dev/null 2>&1; then
    echo "done"
  else
    echo "ERROR (skipping)"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "--- Rebalance complete ---"
echo "Total CIDs: ${TOTAL}"
echo "Errors:     ${ERRORS}"
echo "Run 'docker exec $CN ipfs-cluster-ctl status' to verify."