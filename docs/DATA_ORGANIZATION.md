# Data movement note

The current repository still contains legacy root-level CSV and JSON files.
This branch organizes the active metadata under `data/` so the operational scripts and docs can refer to a single, clear structure.

The repository standard is now:

- `data/batches/` for curated CID files
- `data/projects/` for project metadata CSVs
- `data/reference/` for operational reference JSON files
