# IPFS Cluster Coordinator

Docker Compose deployment for the IPFS Cluster seed/coordinator peer.

## Quick Start

### Coordinator setup

```bash
git clone https://github.com/rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator
cp .env.example .env
# Edit .env: fill in CLUSTER_SECRET, COORDINATOR_PEER_ID
docker network create cluster-internal
docker compose up -d
```

Verify:
```bash
docker exec cluster ipfs-cluster-ctl id
```

### For volunteers

See [`docs/volunteers/GETTING_STARTED.md`](docs/volunteers/GETTING_STARTED.md).

## Default Allocation Model

All new batches use **storage-aware replication** (min 2, max 3):

- Large peers (2 TB) get more pins than small peers (25 GB)
- Peers with no free space keep existing pins but receive no new ones
- The cluster allocator decides placement automatically
- No hardcoded peer exceptions in the standard workflow

## Pinning a Batch

```bash
./scripts/pin-batch.sh data/batches/week42.json
```

See [`docs/PINNING_WORKFLOW.md`](docs/PINNING_WORKFLOW.md) for details.

## Monitor Cluster Health

```bash
./scripts/monitor-cluster.sh
```

See [`docs/MONITORING.md`](docs/MONITORING.md) for details.

## Architecture

```
┌──────────────────────────────┐
│   cluster-internal network   │
│   (Docker network)           │
│                              │
│  cluster:9094 (REST API)     │
│  tracker:9095 (sidecar)      │
└──────────────────────────────┘
```

### Components

| Component | Purpose | Port |
|-----------|---------|------|
| Kubo | IPFS node | 4001 (public), 5001 (local) |
| Cluster | IPFS Cluster daemon | 9096 (public), 9094 (local) |
| Tracker | Failed-CID monitoring | 9095 (local) |

### Network

| Port | Protocol | Public | Purpose |
|------|----------|--------|----------|
| 4001 | TCP+UDP | Yes | IPFS swarm |
| 8081 | TCP | Yes | IPFS gateway |
| 9096 | TCP | Yes | Cluster gossip (for volunteers) |
| 9094 | TCP | **No** | Cluster REST API (internal only) |
| 9095 | TCP | **No** | Tracker REST API (localhost only) |
| 5001 | TCP | **No** | IPFS API (localhost only) |

## Environment Variables

Copy `.env.example` to `.env` and fill in:

| Variable | Description |
|----------|-------------|
| `CLUSTER_SECRET` | 256-bit hex secret shared across all peers |
| `COORDINATOR_PEER_ID` | Peer ID of this coordinator |
| `CLUSTER_PEERNAME` | Human-readable name for this peer |
| `BOOTSTRAP_PEERS` | Empty for coordinator; for volunteers: `/ip4/<ip>/tcp/9096/p2p/<peer-id>` |
| `IPFS_STORAGE_MAX` | Kubo storage ceiling, e.g. `4TB`, `500GB` |
| `POLL_INTERVAL_SECONDS` | Tracker poll interval (default: 60) |

See [`.env.example`](.env.example) for more details.

## Tracker (Failed-CID Monitoring)

A sidecar service monitors the cluster for failed pins:

```bash
docker compose -f docker-compose.tracker.yml up -d
```

Endpoints:
- `GET /summary` → pin counts (pinned/pinning/error/queued)
- `GET /failed-cids` → list of failed CIDs
- `DELETE /failed-cids/{cid}` → retry a failed CID

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Current cluster setup
- [`docs/PINNING_WORKFLOW.md`](docs/PINNING_WORKFLOW.md) — How to add batches
- [`docs/MONITORING.md`](docs/MONITORING.md) — Monitoring cluster health
- [`docs/volunteers/GETTING_STARTED.md`](docs/volunteers/GETTING_STARTED.md) — Volunteer setup (Docker)
- [`docs/volunteers/SYSTEMD_SETUP.md`](docs/volunteers/SYSTEMD_SETUP.md) — Alternative: systemd on existing Kubo
- [`docs/volunteers/ARTBOX_SETUP.md`](docs/volunteers/ARTBOX_SETUP.md) — Special case: ArtBox with separate Kubo
