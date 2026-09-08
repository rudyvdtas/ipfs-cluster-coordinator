#!/bin/sh
set -e

# Raise Kubo's storage ceiling. Default is ~10GB; with cluster peers
# hosting large allocations they need a much higher limit.
# Override via the IPFS_STORAGE_MAX environment variable (e.g. 4TB).
MAX="${IPFS_STORAGE_MAX:-4TB}"

echo "Setting Datastore.StorageMax to ${MAX}"
ipfs config Datastore.StorageMax "${MAX}" || exit 1