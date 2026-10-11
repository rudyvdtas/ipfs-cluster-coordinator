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

## Documentation

| Pad | Omschrijving |
|-----|-------------|
| `docs/ARCHITECTURE.md` | Cluster architectuur en allocatiemodel |
| `docs/PINNING_WORKFLOW.md` | Batch workflow en replicatie-defaults |
| `docs/MONITORING.md` | Monitoring commands en health checks |
| `docs/DATA_ORGANIZATION.md` | Uitleg over de `data/` directorystructuur |
| `docs/IPv6_BOOTSTRAP_SETUP.md` | IPv6 bootstrapping voor peers |
| `docs/NAT_TROUBLESHOOTING.md` | NAT/asymmetrische connectiviteit |
| `docs/STORAGE_SCENARIOS.md` | Opslag-scenarios en rekenformules |
| `docs/LEGACY_DATA.md` | Legacy data — migratie |
| `docs/LEGACY_SCRIPTS.md` | Legacy scripts — referentie |
| `docs/volunteers/GETTING_STARTED.md` | Standaard volunteer setup (Docker) |
| `docs/volunteers/SYSTEMD_SETUP.md` | Systemd-alternatief voor bestaande Kubo |
| `docs/volunteers/ARTBOX_SETUP.md` | ArtBox-specifieke setup met aparte Kubo |

## Notes

- Volunteer documentation is consolidated under `docs/volunteers/`. Root-level volunteer guides have been removed.
- See `LESSONS.md` for operational history, deployment architecture, and production runbooks.
