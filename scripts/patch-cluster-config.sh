#!/bin/sh
# Idempotent patches for ipfs-cluster service.json.
# Safe to run on every boot, on fresh and existing configs.
set -e

SERVICE=/data/ipfs-cluster/service.json

[ -f "$SERVICE" ] || { echo "service.json not found; nothing to patch"; exit 0; }

# --- 1. REST API: listen on all interfaces, plain HTTP ---
# init default is /ip4/127.0.0.1/tcp/9094 (libp2p-http, no plain HTTP).
# The /http suffix enables the plain HTTP transport the dashboard uses.
sed -i 's|/ip4/127.0.0.1/tcp/9094|/ip4/0.0.0.0/tcp/9094/http|' "$SERVICE"

# --- 2. REST API: allow POST/PUT/DELETE (currently GET-only) ---
# Replaces the multiline array  "cors_allowed_methods": [ "GET" ]  with a
# single line of all methods. Idempotent: after the first run the block no
# longer matches the array form.
awk '
  /"cors_allowed_methods": \[/ {
    print "    \"cors_allowed_methods\": [\"GET\", \"POST\", \"PUT\", \"DELETE\"],"
    if ($0 !~ /\]/) in_block = 1
    next
  }
  in_block && /\]/ { in_block = 0; next }
  in_block { next }
  { print }
' "$SERVICE" > "$SERVICE.tmp" && mv "$SERVICE.tmp" "$SERVICE"

# --- 3. Configure trusted peers and pin enforcement ---
SERVICE_FILE="/data/ipfs-cluster/service.json"
if [ ! -f "$SERVICE_FILE" ]; then
  echo "ERROR: $SERVICE_FILE not found. Run ipfs-cluster-service init first." >&2
  exit 1
fi

if [ -z "${COORDINATOR_PEER_ID}" ]; then
  echo "ERROR: COORDINATOR_PEER_ID is not set. Cannot configure trusted peers." >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo "Configuring trusted_peers and pin_only_on_trusted_peers via jq..."
  jq --arg pid "$COORDINATOR_PEER_ID" '
    .consensus.crdt.trusted_peers = [$pid] |
    .cluster.pin_only_on_trusted_peers = true
  ' "$SERVICE_FILE" > "${SERVICE_FILE}.tmp" && mv "${SERVICE_FILE}.tmp" "$SERVICE_FILE"
elif command -v python3 >/dev/null 2>&1; then
  echo "Configuring trusted_peers and pin_only_on_trusted_peers via python3..."
  python3 -c "
import json, sys
with open('$SERVICE_FILE') as f:
    cfg = json.load(f)
cfg.setdefault('consensus', {}).setdefault('crdt', {})['trusted_peers'] = ['$COORDINATOR_PEER_ID']
cfg.setdefault('cluster', {})['pin_only_on_trusted_peers'] = True
with open('$SERVICE_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
"
else
  echo "WARNING: Neither jq nor python3 available. Using awk for JSON patching." >&2
  awk -v pid="$COORDINATOR_PEER_ID" '
    BEGIN { in_consensus=0; in_crdt=0; trusted_done=0; cluster_done=0; pinonly_done=0 }
    
    # Track nesting
    /"consensus"/ { in_consensus=1; print; next }
    in_consensus && /"crdt"/ { in_crdt=1; print; next }
    in_crdt && /}/ { if(!trusted_done) print "    \"trusted_peers\": [\"" pid "\"]"; in_crdt=0; trusted_done=1; print; next }
    in_crdt && /"trusted_peers"/ { print "    \"trusted_peers\": [\"" pid "\"]"; trusted_done=1; next }
    
    in_consensus && /}/ && !/"crdt"/ && !/"consensus"/ { in_consensus=0; if(!trusted_done) print "  },\n  \"crdt\": {\n    \"trusted_peers\": [\"" pid "\"]\n  }"; print; next }
    
    /"cluster"/ { cluster_done=1; print; next }
    cluster_done && /"pin_only"/ { print "    \"pin_only_on_trusted_peers\": true"; pinonly_done=1; next }
    cluster_done && /}/ && !pinonly_done { print "    \"pin_only_on_trusted_peers\": true"; pinonly_done=1; print; next }
    cluster_done && !/^[{}]/ { print; next }
    
    { print }
  ' "$SERVICE_FILE" > "${SERVICE_FILE}.tmp" && mv "${SERVICE_FILE}.tmp" "$SERVICE_FILE"
fi

# Validate JSON
if command -v jq >/dev/null 2>&1; then
  jq . "$SERVICE_FILE" >/dev/null 2>&1 || { echo "ERROR: Invalid JSON after patching" >&2; exit 1; }
fi

echo "trusted_peers configured to [${COORDINATOR_PEER_ID}]"
echo "pin_only_on_trusted_peers set to true"

chown ipfs "$SERVICE"
echo "cluster config patched."