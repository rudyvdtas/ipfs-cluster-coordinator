#!/bin/sh
# DEPRECATED: replaced by scripts/pin-batch.sh
# This script is kept only for historical reference.

cat >&2 <<'EOF'
[DEPRECATED] pin-ko-v2-batch2.sh was replaced by scripts/pin-batch.sh.
Use:
  ./scripts/pin-batch.sh data/batches/<your-batch.json>

The default model is storage-aware cluster allocation with min=2 and max=3 replicas.
EOF

exit 1
