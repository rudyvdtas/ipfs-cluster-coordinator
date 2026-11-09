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

## Deployment (VPS)

The stack must run from a single directory, and that directory must be the git
working copy. Two directories with the same basename share the compose project
name, so starting the stack from the wrong one silently controls the same
containers while your `git pull` lands somewhere else.

Check it before every deploy:

```bash
bash scripts/check-deploy-drift.sh
docker compose ls          # CONFIG FILES shows the directory that is actually live
```

Rules:

- pull in the directory that `docker compose ls` reports, from that directory;
- never hand-edit tracked files in a directory without `.git` — those edits never
  reach git and a later pull will not apply them;
- `.env` exists only in the live directory and is never committed.

### Current setup (since 6 nov 2026)

The stack lives in `/opt/ipfs-cluster-coordinator`, which is the git working copy
at `main`. Deploy workflow:

```bash
# On the VPS, in the live directory:
cd /opt/ipfs-cluster-coordinator
git pull --ff-only origin main
bash scripts/check-deploy-drift.sh          # exit 0 required
docker compose up -d
```

Only `.env` is host-local and never committed. All changes go through
GitHub (feature branch → PR → merge → `git pull` on the VPS).

Raw KOv3 batch source data lives in `/srv/ipfs-data/raw-kov3/` (outside the repo).

## Notes

- Volunteer documentation is consolidated under `docs/volunteers/`. Root-level volunteer guides have been removed.
- See `LESSONS.md` for operational history, deployment architecture, and production runbooks.
