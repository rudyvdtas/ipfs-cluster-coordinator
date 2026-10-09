# Data

This directory contains repository data that is not part of the runtime stack itself.

## Structure

- `data/batches/` — curated CID batch files for pinning workflows
- `data/projects/` — project metadata CSV files
- `data/reference/` — reference JSON files like peer storage and legacy batch metadata

## Standard workflow

The repo standard is now:

```bash
./scripts/pin-batch.sh data/batches/<your-batch.json>
```

This keeps the active workflow separate from project metadata and raw reference artifacts.
