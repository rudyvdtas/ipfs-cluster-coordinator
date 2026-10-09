#!/bin/sh
# DEPRECATED: replaced by scripts/pin-batch.sh
# This script is kept only for historical reference.
# Normal workflow is storage-aware replication with min=2 max=3.

cat >&2 <<'EOF'
[DEPRECATED] sync-cids.sh was replaced by scripts/pin-batch.sh.
Use:
  ./scripts/pin-batch.sh data/batches/<your-batch.json>

The default model is storage-aware cluster allocation with min=2 and max=3 replicas.
EOF

exit 1
