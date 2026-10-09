# Data organization

The repo is organized around a clear separation between operational runtime files and reference/data artifacts.

## Standard structure

```text
data/
├── batches/
├── projects/
└── reference/
```

## Purpose

- `data/batches/` — JSON CID batches used by the batch pinning workflow
- `data/projects/` — CSV or metadata files for collections or project records
- `data/reference/` — peer storage and other supporting reference files

## Repository rule

The standard pinning workflow is:

```bash
./scripts/pin-batch.sh data/batches/<batch.json>
```

This keeps the operational workflow separate from the historical and reference data.
