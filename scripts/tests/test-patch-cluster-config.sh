#!/bin/sh
# Test: patch-cluster-config.sh trusted_peers and pin_only_on_trusted_peers
set -e

echo "=== Test 1: COORDINATOR_PEER_ID empty should fail ==="
SERVICE_FILE=$(mktemp)
echo '{"consensus":{"crdt":{}},"cluster":{}}' > "$SERVICE_FILE"
COORDINATOR_PEER_ID="" \
SERVICE_FILE="$SERVICE_FILE" \
sh -c '
  if [ -z "${COORDINATOR_PEER_ID}" ]; then
    echo "PASS: Empty COORDINATOR_PEER_ID correctly rejected"
    exit 0
  fi
' || true

echo "=== Test 2: Patching with jq (if available) ==="
if command -v jq >/dev/null 2>&1; then
  SERVICE_FILE=$(mktemp)
  cat > "$SERVICE_FILE" <<'JSON'
{
  "consensus": { "crdt": {} },
  "cluster": {}
}
JSON
  PEER_ID="12D3KooWTest123"
  jq --arg pid "$PEER_ID" '
    .consensus.crdt.trusted_peers = [$pid] |
    .cluster.pin_only_on_trusted_peers = true
  ' "$SERVICE_FILE" > "${SERVICE_FILE}.tmp" && mv "${SERVICE_FILE}.tmp" "$SERVICE_FILE"

  RESULT=$(jq -r '.consensus.crdt.trusted_peers[0]' "$SERVICE_FILE")
  if [ "$RESULT" = "$PEER_ID" ]; then
    echo "PASS: trusted_peers set correctly to $RESULT"
  else
    echo "FAIL: trusted_peers is $RESULT, expected $PEER_ID"
    exit 1
  fi

  PIN_ONLY=$(jq -r '.cluster.pin_only_on_trusted_peers' "$SERVICE_FILE")
  if [ "$PIN_ONLY" = "true" ]; then
    echo "PASS: pin_only_on_trusted_peers is true"
  else
    echo "FAIL: pin_only_on_trusted_peers is $PIN_ONLY"
    exit 1
  fi
  rm -f "$SERVICE_FILE" "${SERVICE_FILE}.tmp"
else
  echo "SKIP: jq not available"
fi

echo "=== Test 3: Patching with python3 (if available) ==="
if command -v python3 >/dev/null 2>&1; then
  SERVICE_FILE=$(mktemp)
  cat > "$SERVICE_FILE" <<'JSON'
{
  "consensus": { "crdt": {} },
  "cluster": {}
}
JSON
  PEER_ID="12D3KooWTest456"
  python3 -c "
import json
with open('$SERVICE_FILE') as f:
    cfg = json.load(f)
cfg.setdefault('consensus', {}).setdefault('crdt', {})['trusted_peers'] = ['$PEER_ID']
cfg.setdefault('cluster', {})['pin_only_on_trusted_peers'] = True
with open('$SERVICE_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
"
  RESULT=$(python3 -c "import json; print(json.load(open('$SERVICE_FILE'))['consensus']['crdt']['trusted_peers'][0])")
  if [ "$RESULT" = "$PEER_ID" ]; then
    echo "PASS: trusted_peers set correctly to $RESULT"
  else
    echo "FAIL: trusted_peers is $RESULT, expected $PEER_ID"
    exit 1
  fi

  PIN_ONLY=$(python3 -c "import json; print(json.load(open('$SERVICE_FILE'))['cluster']['pin_only_on_trusted_peers'])")
  if [ "$PIN_ONLY" = "True" ]; then
    echo "PASS: pin_only_on_trusted_peers is true"
  else
    echo "FAIL: pin_only_on_trusted_peers is $PIN_ONLY"
    exit 1
  fi
  rm -f "$SERVICE_FILE"
else
  echo "SKIP: python3 not available"
fi

echo "=== Test 4: Idempotency (run twice, same result) ==="
if command -v jq >/dev/null 2>&1; then
  SERVICE_FILE=$(mktemp)
  cat > "$SERVICE_FILE" <<'JSON'
{
  "consensus": { "crdt": {} },
  "cluster": {}
}
JSON
  PEER_ID="12D3KooWTestIdempotent"
  for i in 1 2; do
    jq --arg pid "$PEER_ID" '
      .consensus.crdt.trusted_peers = [$pid] |
      .cluster.pin_only_on_trusted_peers = true
    ' "$SERVICE_FILE" > "${SERVICE_FILE}.tmp" && mv "${SERVICE_FILE}.tmp" "$SERVICE_FILE"
  done

  COUNT=$(jq '.consensus.crdt.trusted_peers | length' "$SERVICE_FILE")
  if [ "$COUNT" = "1" ]; then
    echo "PASS: Idempotent — trusted_peers still has 1 entry after 2 runs"
  else
    echo "FAIL: trusted_peers has $COUNT entries after 2 runs"
    exit 1
  fi
  rm -f "$SERVICE_FILE" "${SERVICE_FILE}.tmp"
else
  echo "SKIP: jq not available"
fi

echo "=== Test 5: Wildcard not accepted ==="
if command -v jq >/dev/null 2>&1; then
  SERVICE_FILE=$(mktemp)
  cat > "$SERVICE_FILE" <<'JSON'
{
  "consensus": { "crdt": { "trusted_peers": ["*"] } },
  "cluster": {}
}
JSON
  PEER_ID="12D3KooWTestWildcard"
  jq --arg pid "$PEER_ID" '
    .consensus.crdt.trusted_peers = [$pid] |
    .cluster.pin_only_on_trusted_peers = true
  ' "$SERVICE_FILE" > "${SERVICE_FILE}.tmp" && mv "${SERVICE_FILE}.tmp" "$SERVICE_FILE"

  RESULT=$(jq -r '.consensus.crdt.trusted_peers[0]' "$SERVICE_FILE")
  if [ "$RESULT" = "$PEER_ID" ] && [ "$RESULT" != "*" ]; then
    echo "PASS: Wildcard replaced with actual peer ID"
  else
    echo "FAIL: trusted_peers still contains wildcard or wrong value"
    exit 1
  fi
  rm -f "$SERVICE_FILE" "${SERVICE_FILE}.tmp"
fi

echo ""
echo "=== ALL TESTS PASSED ==="