# Pinning workflow

This document describes the intended default batch workflow for the coordinator repository.

## Goal

Keep one simple model for all volunteer batches:

- all volunteers are treated equally
- allocation is storage-aware by free space
- new CID batches are pushed the same way each time
- no hardcoded peer exceptions in the normal workflow

## Default model

The default pinning model is:

- replication min = 2
- replication max = 3
- allocation determined by the cluster allocator based on free space reported by peers

This is the correct default for a mixed fleet of small and large volunteers.

A typical pin will be allocated as follows:
- a large peer (for example 2 TB) gets more pins than a smaller peer
- a small peer (for example 25 GB) gets fewer pins
- a peer that reports no free space does not receive new pins
- if there are too few peers with room, the pin fails rather than silently becoming under-replicated

## Normal workflow

Add a new JSON batch and pin it with the generic script:

```bash
./scripts/pin-batch.sh data/batches/week42-collection.json
```

This keeps the process uniform for all batches:
- no special-case peer IDs
- no special-case allocation logic
- no changes to the operational runtime stack

## Tuning options

For larger or more sensitive batches, you can tune the replication range without changing the generic workflow:

```bash
REPL_MIN=3 REPL_MAX=5 ./scripts/pin-batch.sh data/batches/critical.json
```

For large batches, slow the pin loop to avoid hitting resource limits:

```bash
BATCH_SIZE=20 PAUSE_SECONDS=60 ./scripts/pin-batch.sh data/batches/large-batch.json
```

## Monitoring while batches are added

After a batch is pinned, monitor the cluster state:

```bash
./scripts/monitor-cluster.sh
```

This gives a quick view of:
- number of peers
- current pin count
- per-peer allocation
- capacity status across volunteers

## Important note

This repository branch intentionally keeps the operational production defaults intact and documents the ideal standard workflow rather than replacing live runtime behavior in-place.
