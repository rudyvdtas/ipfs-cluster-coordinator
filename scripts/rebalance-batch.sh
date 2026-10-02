#!/bin/sh
# Batch rebalance — herpint CIDs met replicatiefactor min=2, max=2 (of opgegeven factor).
# Verwerkt in kleine batches (default 100) met pauze (default 60s) om OOM te voorkomen.
# Aanroepen:  ./scripts/rebalance-batch.sh [batch_size] [pause_seconds] [replication_min] [replication_max]
set -e

BATCH="${1:-100}"
SLEEP="${2:-60}"
REPL_MIN="${3:-2}"
REPL_MAX="${4:-2}"

CN=$(docker ps --format '{{.Names}}' | grep -v tracker | grep cluster | head -1)
[ -z "$CN" ] && { echo "Cluster container niet gevonden."; exit 1; }
CLUSTER_CTL="docker exec $CN ipfs-cluster-ctl"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CID_FILE="${SCRIPT_DIR}/../curated-cids.json"

# Lees alle CIDs uit curated-cids.json + kov2-batch01.json als die bestaat
python3 -c "
import json
cids = []
for fn in ['curated-cids.json', 'kov2-batch01.json']:
    try:
        cids.extend(json.load(open(fn)))
    except FileNotFoundError:
        pass
# duplicates eruit, volgorde behouden
seen = set()
uniq = []
for c in cids:
    if c not in seen:
        seen.add(c)
        uniq.append(c)
with open('/tmp/cids.txt', 'w') as f:
    for c in uniq:
        f.write(c + '\n')
print(f'{len(uniq)} unieke CIDs')
"

TOTAL=$(wc -l < /tmp/cids.txt)
echo "Batch: $BATCH, pauze: ${SLEEP}s, replicatie: $REPL_MIN/$REPL_MAX"
echo "Totaal CIDs: $TOTAL"
echo ""

COUNTER=0
ERRORS=0

while read cid; do
  COUNTER=$((COUNTER + 1))
  BATCH_NUM=$(( (COUNTER - 1) / BATCH + 1 ))
  BATCH_POS=$(( (COUNTER - 1) % BATCH + 1 ))

  echo -n "[batch $BATCH_NUM / $BATCH_POS] $cid ... "
  if $CLUSTER_CTL pin add "$cid" \
    --replication-min "$REPL_MIN" \
    --replication-max "$REPL_MAX" \
    >/dev/null 2>&1; then
    echo "done"
  else
    echo "ERROR"
    ERRORS=$((ERRORS + 1))
  fi

  # Pauze na elke batch
  if [ "$BATCH_POS" -eq "$BATCH" ] && [ "$COUNTER" -lt "$TOTAL" ]; then
    echo "  → Pauze ${SLEEP}s ..."
    sleep "$SLEEP"
  fi
done < /tmp/cids.txt

echo ""
echo "--- Rebalance batch complete ---"
echo "Verwerkt: $COUNTER"
echo "Errors:   $ERRORS"
rm /tmp/cids.txt