# Architecture

This document captures the current intended architecture for the cleanup branch.

## Allocation model

The default model is:

- min replication = 2
- max replication = 3
- allocation is storage-aware
a peer with more free space receives more new pins
- peers with no free space keep existing pins but do not receive new ones

This is the standard model for all normal volume uploads.

## Volunteer treatment

All volunteers are treated equally in the default workflow.

- no hardcoded peer exceptions
- no special-case batch assignment in the default path
- large peers naturally receive more content than small peers because the allocator ranks peers by free space

## Operational components

- coordinator: active cluster owner
- volunteers: join and host allocated content
- tracker: monitors failed CIDs
- batch workflow: `scripts/pin-batch.sh`
- monitor: `scripts/monitor-cluster.sh`

## Important note

This branch documents the intended, standard behavior. It is not a rewrite of the live runtime configuration.
