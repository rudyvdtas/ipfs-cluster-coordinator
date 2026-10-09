#!/bin/sh
set -e

echo "[cluster-init] Installing python3 for config patching..."
apk add --no-cache python3 2>&1 | tail -1

echo "[cluster-init] Running config patches..."
/opt/patch-cluster-config.sh

echo "[cluster-init] Starting ipfs-cluster-service..."
exec ipfs-cluster-service daemon --upgrade