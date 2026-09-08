# IPFS Cluster Coordinator

Docker Compose deployment for the IPFS Cluster seed/coordinator peer.
Deployed via Coolify as a "Docker Compose" resource.

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
| `COORDINATOR_PEER_ID` | Peer ID of this coordinator. Only this peer may modify the pinset (`CLUSTER_CRDT_TRUSTEDPEERS`). Get it with `docker exec cluster ipfs-cluster-ctl id` |
| `CLUSTER_PEERNAME` | Human-readable name for this peer |
| `BOOTSTRAP_PEERS` | Empty for the seed peer. For followers: `/ip4/<seed-ip>/tcp/9096/p2p/<seed-peer-id>` |

In Coolify, set `CLUSTER_SECRET` and `COORDINATOR_PEER_ID` via the **Secrets** UI (not in the compose file).

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
| 8080 | TCP | Yes | IPFS gateway |
| 9096 | TCP | Yes | Cluster gossip (followers connect here) |
| 9094 | TCP | **No** | Cluster REST API (internal only, via `cluster-internal` network) |
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
```