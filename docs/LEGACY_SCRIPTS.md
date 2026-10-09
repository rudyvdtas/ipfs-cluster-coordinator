# Legacy notes

The repository default is now the storage-aware batch workflow.

Deprecated scripts are intentionally left in place as blockers so they cannot be run accidentally.
The active workflow is:

  ./scripts/pin-batch.sh data/batches/<your-batch.json>

This uses the cluster allocator to distribute pins across volunteers by free space, with min 2 and max 3 replicas.
