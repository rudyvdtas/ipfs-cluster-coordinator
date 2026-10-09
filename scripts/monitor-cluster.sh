#!/bin/bash
# Quick cluster health and growth check.
#
# Usage:
#   ./scripts/monitor-cluster.sh

set -e

CLUSTER_CTL="docker exec cluster ipfs-cluster-ctl"

printf "=== Cluster Status ===\n\n"
PEER_COUNT=$(${CLUSTER_CTL} peers ls 2>/dev/null | wc -l | tr -d ' ')
printf "📍 Peers: %s\n\n" "$PEER_COUNT"

TOTAL_PINS=$(${CLUSTER_CTL} status 2>/dev/null | grep -c "pinned" || echo 0)
printf "📌 Total pins: %s\n\n" "$TOTAL_PINS"

printf "👥 Per-peer allocation:\n"
${CLUSTER_CTL} status 2>/dev/null | grep "> " | awk '{print $NF}' | sort | uniq -c | sort -rn | while read -r count peer; do
  printf "   %4s pins  %s\n" "$count" "$peer"
done

printf "\n💾 Storage summary:\n"
if [ -f "peer-storage.json" ]; then
  python3 - <<'PY'
import json

with open('peer-storage.json') as f:
    cfg = json.load(f)

for name, info in cfg['peers'].items():
    smax = info.get('storage_max')
    if smax is None:
        label = '∞'
    else:
        label = f"{smax / 1e9:.0f}GB"
    print(f"   {name:20s} {label:>6s}")
PY
else
  echo "   no peer-storage.json found"
fi
