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

chown ipfs "$SERVICE"
echo "cluster config patched."