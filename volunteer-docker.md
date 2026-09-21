# Volunteer — Full setup (Docker)

Set up a completely new peer via Docker, including Kubo (IPFS) and IPFS Cluster.

## What you will do

You start two Docker containers (Kubo + IPFS Cluster) on your own machine.
They connect to the existing cluster, get assigned a share of the curated
CIDs, and automatically download and host them.

You are **read-only**: you cannot add or remove CIDs.

## Requirements

- Linux (VPS, Raspberry Pi 3/4/5, old laptop) — ARM64 or AMD64
- RAM: at least 1.5–2 GB (Kubo + Cluster together ~500 MB–1 GB idle)
- Disk space: configurable via `IPFS_STORAGE_MAX`
- Docker
- Cluster secret + bootstrap address (shared by the coordinator after sign-up)

## Step by step

### 1. Install Docker (skip if you already have it)

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Clone the coordinator repository

```bash
git clone https://github.com/rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator
```

### 3. Create your configuration file

```bash
cp .env.example .env
nano .env
```

Fill in the following fields:

```
CLUSTER_SECRET=<the secret the coordinator shared with you>
CLUSTER_PEERNAME=choose-a-unique-name
COORDINATOR_PEER_ID=12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
IPFS_STORAGE_MAX=200GB
BOOTSTRAP_PEERS=/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
# Only needed if you are behind NAT — set to your public or Tailscale IP:
# CLUSTER_PEER_ADDRESSES=/ip4/<your-public-or-tailscale-ip>/tcp/9096
```

> `COORDINATOR_PEER_ID` is the coordinator's peer ID. It enables the cluster
> to restrict pinset writes to the coordinator only via CRDT trusted peers.
> Volunteers receive allocations and host content but cannot add or remove CIDs.

### 4. Open the firewall

```bash
sudo ufw allow 4001/tcp
sudo ufw allow 4001/udp
sudo ufw allow 9096/tcp  # only needed behind NAT
```

### 5. Start

```bash
docker network create cluster-internal
docker compose up -d
```

### 6. Verify the connection

```bash
docker exec cluster ipfs-cluster-ctl id
```

If you see a valid peer ID, you are connected.

## What happens next

Once the coordinator sees your peer is active, the replication factor is
increased so CIDs are distributed to your node. You start automatically
downloading and hosting.

Check with:

```bash
docker exec cluster ipfs-cluster-ctl peers ls
docker exec cluster ipfs-cluster-ctl status
```

Live dashboard: **[https://glimmy.xyz](https://glimmy.xyz)**