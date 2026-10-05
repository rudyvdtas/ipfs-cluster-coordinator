#!/bin/sh
# Storage-aware rebalance — verdeelt CIDs over peers die genoeg ruimte hebben.
# Leest per-peer opslaglimieten uit peer-storage.json.
# Alleen peers met voldoende vrije ruimte tellen mee voor de replicatiefactor.
set -e

CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/../peer-storage.json"
CID_FILE="$(cd "$(dirname "$0")" && pwd)/../curated-cids.json"

# --- Config defaults ---
MIN_REPLICA=${MIN_REPLICA:-2}
MAX_REPLICA=${MAX_REPLICA:-3}
CID_SIZE_GB=${CID_SIZE_GB:-0.001}  # geschatte grootte per CID in GB (~1MB/CID o.b.v. 754MB/4010 obj)

# --- Vind cluster container ---
CN=$(docker ps --format '{{.Names}}' | grep -v tracker | grep cluster | head -1)
[ -z "$CN" ] && { echo "Cluster container niet gevonden."; exit 1; }
CLUSTER_CTL="docker exec $CN ipfs-cluster-ctl"

echo "=== Storage-aware rebalance ==="
echo ""

# --- Lees peer-storage config ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "peer-storage.json niet gevonden op $CONFIG_FILE"
  echo "Maak hem aan of run met STORAGE_JSON=/pad/naar/bestand"
  exit 1
fi

# --- Parse peer config met python ---
STORAGE_INFO=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
for name, info in cfg['peers'].items():
    smax = info['storage_max']
    label = f'{smax:,}' if smax else 'unlimited'
    print(f'{name}|{info[\"peer_id\"]}|{smax if smax else 0}|{label}|{info[\"notes\"]}')
")

echo "Geconfigureerde peers (uit peer-storage.json):"
echo "$STORAGE_INFO" | while IFS='|' read name pid smax label notes; do
  echo "  $name ($label) — $notes"
done
echo ""

# --- Haal huidige allocaties op uit cluster ---
echo "Huidige allocaties per peer (via ipfs-cluster-ctl status)..."
ALLOC_DATA=$(mktemp)
$CLUSTER_CTL status 2>/dev/null > "$ALLOC_DATA"

# Tel aantal CIDs per peer
echo "$STORAGE_INFO" | while IFS='|' read name pid smax label notes; do
  COUNT=$(grep -c "> $name" "$ALLOC_DATA" 2>/dev/null || echo 0)
  EST_GB=$((COUNT * CID_SIZE_GB))
  if [ "$smax" -gt 0 ] 2>/dev/null; then
    EST_BYTES=$((EST_GB * 1000000000))
    PCT=$(( EST_BYTES * 100 / smax ))
    FREE_GB=$(( (smax - EST_BYTES) / 1000000000 ))
    echo "  $name: $COUNT CIDs (~${EST_GB}GB, ${PCT}% gebruikt, ~${FREE_GB}GB vrij)"
  else
    echo "  $name: $COUNT CIDs (~${EST_GB}GB, onbeperkt)"
  fi
done
rm "$ALLOC_DATA"
echo ""

# --- Bepaal welke peers nog CIDs kunnen ontvangen ---
QUALIFIED=$(python3 -c "
import json

CID_SIZE_BYTES = ${CID_SIZE_GB} * 1000000000
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)

qualified = []
for name, info in cfg['peers'].items():
    smax = info['storage_max']
    # Peers zonder limiet tellen altijd mee
    if smax is None:
        qualified.append(name)
        continue
    # Minimaal 10 CIDs moeten passen
    max_cids = int(smax // CID_SIZE_BYTES)
    if max_cids >= 10:
        qualified.append(name)

print(' '.join(qualified))
")

QUALIFIED_COUNT=$(echo "$QUALIFIED" | wc -w | tr -d ' ')
TOTAL_PEERS=$(echo "$STORAGE_INFO" | wc -l)

echo "=== Replicatieplan ==="
echo "  Totaal peers in cluster: $TOTAL_PEERS"
echo "  Peers met voldoende ruimte: $QUALIFIED_COUNT"
echo "  Uitgesloten (te weinig ruimte):"
for p in $QUALIFIED; do
  :
done
# Inverse: toon peers die NIET in qualified zitten
echo "$STORAGE_INFO" | while IFS='|' read name pid smax label notes; do
  FOUND=0
  for q in $QUALIFIED; do
    if [ "$q" = "$name" ]; then
      FOUND=1
      break
    fi
  done
  if [ "$FOUND" -eq 0 ]; then
    echo "    - $name ($label, $notes)"
  fi
done

# --- Bereken target replicatie ---
TARGET=$QUALIFIED_COUNT
if [ "$TARGET" -gt "$MAX_REPLICA" ]; then
  TARGET=$MAX_REPLICA
fi
if [ "$TARGET" -lt "$MIN_REPLICA" ]; then
  echo ""
  echo "⚠  Slechts $QUALIFIED_COUNT peer(s) hebben genoeg ruimte voor replicatie $MIN_REPLICA."
  echo "   Verlaag MIN_REPLICA of voeg meer opslag toe aan peers."
  if [ "$TARGET" -lt 2 ]; then
    echo "   Minder dan 2 peers beschikbaar — kan geen redundantie garanderen."
  fi
  TARGET=$QUALIFIED_COUNT
fi

echo "  Doel-replicatie: min=$TARGET, max=$TARGET"
echo ""

# --- Lees CIDs ---
if [ ! -f "$CID_FILE" ]; then
  echo "curated-cids.json niet gevonden op $CID_FILE"
  exit 1
fi

TOTAL=$(python3 -c "import json; print(len(json.load(open('${CID_FILE}', 'r'))))" 2>/dev/null || echo 0)
echo "Rebalancing ${TOTAL} CIDs naar replicatie=${TARGET}..."
echo ""

COUNTER=0
ERRORS=0

for cid in $(python3 -c "
import json
for c in json.load(open('${CID_FILE}', 'r')): print(c)
" 2>/dev/null); do
  COUNTER=$((COUNTER + 1))
  echo -n "[${COUNTER}/${TOTAL}] ${cid} ... "
  if $CLUSTER_CTL pin add "${cid}" \
    --replication-min "${TARGET}" \
    --replication-max "${TARGET}" \
    >/dev/null 2>&1; then
    echo "done (replica=$TARGET)"
  else
    echo "ERROR (skipping)"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "=== Rebalance complete ==="
echo "  Verwerkt: $COUNTER"
echo "  Errors:   $ERRORS"
echo "  Replicatie: $TARGET"
echo "  Peers in replicatieplan: $QUALIFIED"
echo ""
echo "Run 'docker exec $CN ipfs-cluster-ctl status' to verify."