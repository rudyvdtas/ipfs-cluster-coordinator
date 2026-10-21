# Monitoring

This document describes a lightweight monitoring workflow for checking cluster health and growth while batches are added.

ssh root@149.210.143.16

## Cluster health check

```bash
./scripts/monitor-cluster.sh
```

This script prints:
- peer count
- total pin count
- per-peer allocation count
- peer storage capacity summary

## Volunteer health and pin counts

Volunteers show up as peers in the coordinator's cluster. The CLI keeps a concise health/status table and lets you count how many active allocations each volunteer currently hosts.

### Volunteer status

```bash
docker exec cluster ipfs-cluster-ctl peers ls
```

The default table lists `Peer`, `Name`, `Status`, `Error`, and the gossip `Address`. Look for `Status: connected` and an empty `Error` field to confirm the peer is healthy; `unresponsive` or `disconnected` entries need investigation on that volunteer node (network, firewall, version mismatch, disk pressure, …).

If you prefer structured output, add `--enc json` and pipe into `jq` (or another JSON parser) to group by status or filter for volunteers whose `status.error` is populated:

```bash
docker exec cluster ipfs-cluster-ctl peers ls --enc json | jq -r '.[] | "\(.name // \"<unnamed>\")\t\(.status)\t\(.error // \"ok\")"'
```

### Per-volunteer pin counts

```bash
docker exec cluster ipfs-cluster-ctl status | grep "> " | awk '{print $NF}' | sort | uniq -c | sort -rn
```

This command prints the number of pinned CIDs currently assigned to each peer (the same data that `./scripts/monitor-cluster.sh` summarizes under “Per-peer allocation”). Use `peers ls` to map the peer IDs in this report back to the volunteer’s friendly name and address.

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
