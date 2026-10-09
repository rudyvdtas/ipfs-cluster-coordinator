# Legacy data notes

This branch intentionally keeps a clean separation between:

- active workflow files
- historical or legacy files
- data files used for reference

The main cleanup principle is:

- standard workflow = `scripts/pin-batch.sh`
- legacy batch scripts are deprecated and intentionally blocked
- root-level raw data is organized under `data/`

This is a documentation branch, not a runtime rewrite branch.
