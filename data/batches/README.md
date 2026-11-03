# Batches

This directory stores the CID JSON lists used by the cluster batch workflow.

These files are intended to be used via:

```bash
./scripts/pin-batch.sh data/batches/<file>.json
```

## Current batch files

- `curated-cids.json`
- `curated-cids-async-first-supper.json`
- `curated-cids-knownorigin.json`
- `curated-cids-the-arcana.json`
- `curated-cids-ko-v2-batch2.json`
- `curated-cids-ko-v2-batch3.json`
- `curated-cids-ko-v3-batch01.json` … `curated-cids-ko-v3-batch21.json`

The `ko-v3` files are generated from the `kov3_batch_NN_*.csv` exports (one CID per
row, first column) and hold 830–1.150 CIDs each, roughly 10 GB per batch.

## Pinning KOv3 batches

`pin-batch.sh` uses the cluster allocator, which may also allocate to the
coordinator. For KOv3 use the explicit-allocation variant instead:

```bash
bash scripts/pin-ko-v3-batch.sh                          # batch 09-21, vernis + zomi + pi
ALLOCATIONS="<vernis>,<zomi>" START_BATCH=31 END_BATCH=63 bash scripts/pin-ko-v3-batch.sh
```
