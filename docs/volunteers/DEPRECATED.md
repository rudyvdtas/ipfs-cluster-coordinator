# Deprecated Volunteer Docs

This folder consolidates the standard volunteer setup paths.

The following older documents remain in the repo root for reference but are **superseded** by the current documentation:

- `volunteer_cluster.md` — superseded by `docs/volunteers/GETTING_STARTED.md` (Docker, standard setup)
- `volunteer-docker.md` — superseded by `docs/volunteers/GETTING_STARTED.md` (same as above)
- `volunteer-existing-ipfs.md` — superseded by `docs/volunteers/SYSTEMD_SETUP.md` (systemd alternative)
- `volunteer-artbox.md` — superseded by `docs/volunteers/ARTBOX_SETUP.md` (ArtBox special case)
- `how-to-cluster-artbox.md` — superseded by `docs/volunteers/ARTBOX_SETUP.md` (same as above)

## Consolidation

All volunteer setup paths are now unified under `docs/volunteers/` with clear naming:

1. **Standard Docker setup** → `GETTING_STARTED.md`
2. **Systemd on existing Kubo** → `SYSTEMD_SETUP.md`
3. **ArtBox with separate Kubo** → `ARTBOX_SETUP.md`

Each document is self-contained and complete. No cross-references to outdated files.
