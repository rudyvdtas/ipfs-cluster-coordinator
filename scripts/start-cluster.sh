#!/bin/sh
set -e

chown -R ipfs /data/ipfs-cluster 2>/dev/null || true

if [ ! -f /data/ipfs-cluster/service.json ]; then
  echo "Initializing ipfs-cluster configuration..."
  ipfs-cluster-service init --consensus "${IPFS_CLUSTER_CONSENSUS:-crdt}"
fi

if [ -f /opt/patch-cluster-config.sh ]; then
  chmod +x /opt/patch-cluster-config.sh
  /opt/patch-cluster-config.sh
fi

chown ipfs /data/ipfs-cluster/service.json 2>/dev/null || true

exec ipfs-cluster-service daemon