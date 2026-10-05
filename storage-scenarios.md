# Storage scenarios — IPFS Cluster volunteers

## Formulas

- **Total stored** = dataset size × replication factor
- **Average per node** = (dataset × replication) / number of volunteers
- **Max dataset for given nodes** = (volunteers × 2TB) / replication

## Assumptions

- Each volunteer: **2 TB** available
- Current CIDs: **111 items** (total size unknown)

## Scenarios

| volunteers | total storage | replication | max dataset | per node load |
|-----------|---------------|-----------|------------|-------------|
| 7 | 14 TB | 2× | 7.00 TB | dataset × 0.29 |
| 7 | 14 TB | 3× | 4.67 TB | dataset × 0.43 |
| 7 | 14 TB | 5× | 2.80 TB | dataset × 0.71 |
| 7 | 14 TB | 7× | 2.00 TB | dataset × 1.00 |
| 20 | 40 TB | 3× | 13.33 TB | dataset × 0.15 |
| 20 | 40 TB | 5× | 8.00 TB | dataset × 0.25 |
| 20 | 40 TB | 7× | 5.71 TB | dataset × 0.35 |
| 30 | 60 TB | 5× | 12.00 TB | dataset × 0.17 |
| 30 | 60 TB | 7× | 8.57 TB | dataset × 0.23 |

## Example: 5 TB dataset

| volunteers | replication | total stored | per node | fits? |
|-----------|-------------|-------------|---------|-------|
| 7 | 2× | 10 TB | 1.43 TB | ✅ |
| 7 | 3× | 15 TB | 2.14 TB | ❌ (hits limit) |
| 7 | 5× | 25 TB | 3.57 TB | ❌ |
| 13 | 5× | 25 TB | 1.92 TB | ✅ |
| 20 | 5× | 25 TB | 1.25 TB | ✅ plenty |
| 30 | 5× | 25 TB | 0.83 TB | ✅ plenty |

## Minimum nodes needed (2 TB each)

| dataset | replication 3× | replication 5× | replication 7× |
|---------|--------------|--------------|--------------|
| 0.5 TB | 1 | 2 | 2 |
| 1.0 TB | 2 | 3 | 4 |
| 2.0 TB | 3 | 5 | 7 |
| 5.0 TB | 8 | 13 | 18 |
| 10.0 TB | 15 | 25 | 35 |

## Key takeaways

- **More volunteers = lower load per node** at the same replication factor
- **7 volunteers × 2TB** is tight at replication 5 once the dataset exceeds ~2.8 TB
- **20-30 volunteers** provides strong distribution: at 5 TB and rep 5, per-node load is only 0.83-1.25 TB
- Adjust replication via: `./scripts/sync-cids.sh <min> <max>` (e.g. `./scripts/sync-cids.sh 5 5`)