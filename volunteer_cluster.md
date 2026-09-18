# Become a Volunteer — IPFS Cluster (DRL coordinator · TheGuild)

Thank you for helping out! Below you'll find what it means, what you need,
and how to set up a peer in ~10 minutes that automatically hosts part of
the curated content.

## What exactly will you do?

You start a small program (via Docker) on your own machine. That program
connects to the existing cluster, gets assigned a share of the 110+ curated
CIDs, and automatically downloads and hosts them. You don't have to manage
or choose anything — the cluster handles the distribution. You are **read
only** and can only replicate; you cannot add or remove CIDs yourself.

## Requirements

| Requirement | Detail |
|---|---|
| Machine | Linux (VPS, Raspberry Pi 3/4/5, old laptop) — ARM64 or AMD64 |
| RAM | At least 1.5–2 GB (Kubo + Cluster together use ~500 MB–1 GB idle) |
| Disk space | As much as you want to contribute, configurable via `IPFS_STORAGE_MAX` |
| Software | Docker |
| Access | The cluster secret (I will share this privately with you) |

`ipfs/kubo` and `ipfs/ipfs-cluster` are multi-arch images: Docker
automatically pulls the correct version for your architecture, so you
don't need to configure anything for that.

## Step by step

### 1. Install Docker (skip if you already have it)

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Clone the repository

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
CLUSTER_SECRET=<the secret I will share with you privately>
CLUSTER_PEERNAME=choose-a-unique-name         # e.g. "jan-vps" — for identification only
COORDINATOR_PEER_ID=12D3KooWHFTWFc97iyXyPEPX1Rxs1AaUxk2a6rDdkRQBUfybsfok
IPFS_STORAGE_MAX=200GB                         # how much you want to contribute; leave empty for 4TB default
BOOTSTRAP_PEERS=/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWHFTWFc97iyXyPEPX1Rxs1AaUxk2a6rDdkRQBUfybsfok
# Only needed if you are behind NAT (home network, Docker Desktop, etc.).
# Set this to your public IP or Tailscale IP so the coordinator can reach you back.
# CLUSTER_PEER_ADDRESSES=/ip4/<your-public-or-tailscale-ip>/tcp/9096
```

Save and exit (in nano: `Ctrl+O`, `Enter`, `Ctrl+X`).

### 4. Open the required port in your firewall

```bash
sudo ufw allow 4001/tcp
sudo ufw allow 4001/udp
```

This is the port your node uses to communicate with other peers.
Do not skip this step — without an open port your node cannot connect
to the cluster.

**Also open port 9096/tcp** if you are behind NAT (home router, Docker on macOS, etc.):

```bash
sudo ufw allow 9096/tcp
```

Then tell your router to forward port 9096 to this machine. Without this,
the coordinator cannot reach back to your peer for CRDT sync and metrics.
If your machine has a public IP, also set `CLUSTER_PEER_ADDRESSES` in `.env`
(see step 3).

### 5. Create the Docker network and start

```bash
docker network create cluster-internal
docker compose up -d
```

### 6. Check that you are connected

```bash
docker exec cluster ipfs-cluster-ctl id
```

If you see a valid peer ID and no error message, your node is running
correctly and is visible to the cluster.

## What happens next

Once I see your peer is connected, I will increase the replication factor
so that the content is distributed across both peers. From that point on,
each CID is stored on at least 2 peers (you + the coordinator) — that is
the goal: **redundancy**.

This does not happen automatically when your node starts; it is a manual
step on my side, so it may take some time before you actually start
downloading and hosting data.

## Verify everything works

```bash
docker exec cluster ipfs-cluster-ctl peers ls      # see coordinator + other peers
docker exec cluster ipfs-cluster-ctl status         # status of all pinned CIDs
```

Live cluster status dashboard: **[https://glimmy.xyz](https://glimmy.xyz)**

## Frequently asked questions

**I get an error with `docker compose up -d`.**
Check that Docker is running (`docker ps` should work without errors) and
that you are in the correct directory (`ipfs-cluster-coordinator`).

**`ipfs-cluster-ctl id` gives no output or hangs.**
Usually a firewall or port issue — check step 4, and verify that your
hosting provider does not block port 4001 at the network level (some
VPS providers do this separately from `ufw`).

**How much data traffic should I expect?**
That depends on how much you contribute via `IPFS_STORAGE_MAX` and how
often content is requested by others. Feel free to start with a smaller
amount.

**Can I see which CIDs I am hosting?**
Yes, via `docker exec cluster ipfs-cluster-ctl status` (step 6 above).

## Questions?

Contact me through the usual channels.