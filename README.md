# IPFS Cluster Coordinator

This repository contains the coordinator and its operational helper scripts.

## Default model

The standard production model for all normal batches is:

- storage-aware allocation across volunteers
- replication min = 2
- replication max = 3
- no hardcoded peer exceptions in the default workflow

This means the cluster allocator decides where to place each CID based on current free space per peer.

## Standard batch workflow

```bash
./scripts/pin-batch.sh data/batches/<your-batch.json>
```

This is the active workflow for all new batch uploads.

## Monitoring

```bash
./scripts/monitor-cluster.sh
```

See `docs/MONITORING.md` for cluster health checks.

## Documentation

- `docs/ARCHITECTURE.md` — current cluster architecture and allocation model
- `docs/PINNING_WORKFLOW.md` — batch workflow and replication defaults
- `docs/MONITORING.md` — monitoring commands and health checks
- `docs/volunteers/GETTING_STARTED.md` — standard volunteer setup
- `docs/volunteers/SYSTEMD_SETUP.md` — systemd alternative for existing Kubo
- `docs/volunteers/ARTBOX_SETUP.md` — ArtBox-specific setup with separate Kubo

## Data layout

```text
data/
├── batches/
├── projects/
└── reference/
```

## Notes

- Legacy batch scripts are intentionally deprecated and blocked in this branch.
- The runtime stack itself remains separate from the repository cleanup work and is intentionally not rewritten in-place.
