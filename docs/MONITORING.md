# Monitoring

This document describes a lightweight monitoring workflow for checking cluster health and growth while batches are added.

## Cluster health check

```bash
./scripts/monitor-cluster.sh
```

This script prints:
- peer count
- total pin count
- per-peer allocation count
- peer storage capacity summary

## Tracker status

The tracker sidecar exposes cached aggregate data:

```bash
curl http://127.0.0.1:9095/summary
```

A normal response includes counts such as:
- pinned
- pinning
- queued
- error
- pin_count

## Per-CID debugging

To inspect a specific CID in the active cluster:

```bash
docker exec cluster ipfs-cluster-ctl status | grep QmYOURCID
```

## Logs

To inspect logs while a batch is being pinned:

```bash
docker logs cluster --tail 100
```

For the tracker:

```bash
docker logs tracker --tail 100
```

## Why monitor after each batch?

The goal is to observe whether the cluster remains stable when loads increase.

The usual checks are:
- peer count remains stable
- new pins are allocated within the cluster
- no peer falls into a repeated error loop
- large peers continue to receive more allocations than small peers in the expected storage-aware pattern
