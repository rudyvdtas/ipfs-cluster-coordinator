# IPFS Cluster Coordinator

Docker Compose deployment for the IPFS Cluster seed/coordinator peer.

## Prerequisites

Create the shared Docker network once on the host:

```
docker network create cluster-internal
```

## Environment variables

Copy `.env.example` to `.env` and fill in:

| Variable | Description |
|----------|-------------|
| `CLUSTER_SECRET` | 256-bit hex secret shared across all peers. Generate: `od -vN 32 -An -tx1 /dev/urandom \| tr -d ' \n'` |
| `COORDINATOR_PEER_ID` | Peer ID of this coordinator. Used by `CLUSTER_CRDT_TRUSTEDPEERS` and to patch `trusted_peers` + `pin_only_on_trusted_peers` in `service.json`, so only this peer controls the pinset. Get it with `docker exec cluster ipfs-cluster-ctl id` |
| `CLUSTER_PEERNAME` | Human-readable name for this peer |
| `BOOTSTRAP_PEERS` | Empty for the seed peer. For followers: `/ip4/<seed-ip>/tcp/9096/p2p/<seed-peer-id>` |
| `IPFS_STORAGE_MAX` | Kubo storage ceiling, e.g. `4TB`, `500GB`. Default: `4TB`. |
| `POLL_INTERVAL_SECONDS` | Tracker poll interval (see tracker section below). Default: `60`. |

Set `CLUSTER_SECRET` and `COORDINATOR_PEER_ID` via secrets management
(not in the compose file).

## Roles

| | Coordinator | Volunteer peer |
|---|---|---|
| Modify pinset (add/remove CIDs) | ✅ | ❌ |
| Store allocated content | ✅ | ✅ |
| Join the cluster | ✅ | ✅ |

The cluster distributes pin allocations automatically across peers via
`replication_factor_min` / `replication_factor_max`. Volunteers receive
allocations and host content; only the coordinator controls the pinset.

## Deploy

```
docker compose up -d
```

Draait in productie op de VPS vanuit `/opt/ipfs-cluster-coordinator` via plain
`docker compose` (niet via Coolify — zie `LESSONS.md`). Na elke `git pull`:

```
docker compose up -d
```

## Tracker (failed-CID sidecar)

Naast de cluster draait een tracker-service (`track-failed-cids.py`) in een
aparte Docker container. Deze:

- Pollt elke `POLL_INTERVAL_SECONDS` de cluster REST API (`GET /pins`) voor
  pin-status
- Houdt per-CID error counts bij; na `MAX_RETRIES` errors wordt de CID
  automatisch ge-unpind en aan de failed-lijst toegevoegd
- Biedt `GET /summary` aan (cached, geen live broadcast) — gebruikt door de
  monitor voor tellingen

Start de tracker met:

```
docker compose -f docker-compose.tracker.yml up -d
```

### Tracker endpoints

| Endpoint | Beschrijving |
|----------|--------------|
| `GET /failed-cids` | JSON array van gefaalde CIDs |
| `GET /summary` | Cached aggregate pin-status counts |
| `GET /status` | Debug: error_counts + failed_count |
| `GET /healthz` | `{"status": "ok"}` |
| `DELETE /failed-cids/{cid}` | Verwijder van failed lijst (manual retry) |

## Get the peer address (for followers)

```
docker exec cluster ipfs-cluster-ctl id
```

Note the peer ID from the output. The bootstrap multiaddr for follower peers is:

```
/ip4/<this-machine-public-ip>/tcp/9096/p2p/<peer-id>
```

## Network

| Port | Protocol | Public | Purpose |
|------|----------|--------|---------|
| 4001 | TCP+UDP | Yes | IPFS swarm |
| 8081 | TCP | Yes | IPFS gateway |
| 9096 | TCP | Yes | Cluster gossip (followers connect here) |
| 9094 | TCP | **No** | Cluster REST API — `cluster-internal` Docker network + `127.0.0.1` only (for the host-level monitor process, see `sveltekit-monitor-app`) |
| 9095 | TCP | **No** | Tracker REST API (localhost only) |
| 5001 | TCP | **No** | IPFS API (localhost only) |

## Architecture

```
                    ┌──────────────────────────┐
                    │   cluster-internal net   │
                    │   (docker network)       │
                    │                          │
                    │  cluster:9094            │
                    │  (REST API, no host port)│
                    └──────────┬───────────────┘
                               │
                               │ HTTP
                               │
                    ┌──────────▼───────────────┐
                    │  sveltekit-monitor-app   │
                    │  (separate repo)         │
                    └──────────────────────────┘

                    ┌──────────────────────────┐
                    │  tracker:9095            │
                    │  (failed-CID sidecar)    │
                    │  Polls cluster:9094      │
                    │  Exposes /summary        │
                    └──────────────────────────┘
```