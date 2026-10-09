# Architecture

This document describes the current production architecture as it is implemented in the coordinator repository, without changing the live runtime configuration.

## Cluster role

The cluster is a coordination and pinning system for volunteers and the coordinator peer.

- Coordinator: the authoritative pinset owner
- Volunteers: join the cluster and host allocated content
- The coordinator controls pinset changes
- Volunteers do not add or remove pins directly

## Allocation model

The production default is storage-aware allocation, not hardcoded peer assignments.

The cluster allocates new pins based on free space reported by peers.

This means:
- a 2 TB peer gets more pins than a 25 GB peer
- a peer with no free space keeps existing pins but does not receive new ones
- if there are too few peers with capacity, the pin may fail instead of being under-replicated

This is the intended default for new batches.

## Production defaults

- replication min: 2
- replication max: 3
- batch pinning: storage-aware, cluster allocator decides placement
- no hardcoded peer exceptions in the normal workflow

## Runtime components

- `docker-compose.yaml`: the active runtime stack
- `track-failed-cids.py`: tracker sidecar for failed-CID monitoring
- `docker-compose.tracker.yml`: tracker service config
- `scripts/patch-cluster-config.sh`: service.json patching for boot-time config fixes

## Important notes

- The runtime stack should remain stable until the production fix set is intentionally applied.
- The generic batch workflow in this branch is intentionally additive and does not replace the current live runtime files.
- This branch is for clean-up, documentation, and a standard batch workflow only.

## Source of truth for pinning

The current runtime still depends on the live cluster state plus the CID JSON files used by the operational scripts.

For the cleanup and standardization effort, the intended default is:

- one batch script for all JSON collections
- one storage-aware workflow for all volunteers
- no hardcoded peer-specific pinning in normal operations
