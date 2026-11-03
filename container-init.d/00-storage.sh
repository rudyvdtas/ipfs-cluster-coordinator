#!/bin/sh
set -e

# Set Kubo's storage ceiling. The default is sized for the coordinator, which
# must not host content: peers that only coordinate get 5GB. Volunteers MUST
# set IPFS_STORAGE_MAX explicitly (e.g. 200GB) or they will stall at 5GB.
MAX="${IPFS_STORAGE_MAX:-5GB}"

echo "Setting Datastore.StorageMax to ${MAX}"
ipfs config Datastore.StorageMax "${MAX}" || exit 1