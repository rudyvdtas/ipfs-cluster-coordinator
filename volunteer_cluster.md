# Become a Volunteer — IPFS Cluster (DRL coordinator · TheGuild)

Thank you for helping out! Here's how it works: you reach out, the coordinator
shares the cluster secret and bootstrap address with you, and you set up a peer
in ~10 minutes that automatically hosts part of the curated content.

## What exactly will you do?

You start a small program (via Docker) on your own machine. That program
connects to the existing cluster, gets assigned a share of the 110+ curated
CIDs, and automatically downloads and hosts them. You don't have to manage or
choose anything — the cluster assigns CIDs based on which ones currently have
the fewest replicas, so new volunteers immediately improve overall redundancy.

**Trust model:** Volunteers join after the coordinator shares the cluster secret
and bootstrap address — there is no open sign-up. The secret is the access gate.

Your peer runs in **follower mode** (`CLUSTER_FOLLOWERMODE=true`), which means
you can join the cluster, receive allocations, and host content, but local pin
and unpin operations are **technically disabled**. Only the coordinator can
manage the pinset.

The coordinator manages the single source of truth:
[`curated-cids.json`](https://github.com/rudyvdtas/ipfs-cluster-coordinator/blob/main/curated-cids.json).
The full CID list is always public and reviewable there and on the
[live dashboard](https://glimmy.xyz/projects). All CIDs are on-chain art
and metadata indexed by CyberWatch·TheGuild.

The cluster assigns CIDs based on which ones currently have the fewest replicas,
so new volunteers immediately improve overall redundancy. You decide how much
disk space you contribute; CIDs are allocated accordingly.

The goal: each CID replicated across at least 5 independent volunteers, so no
single node failure causes content loss.

## Requirements

| Requirement | Detail |
|---|---|
| Machine | Linux (VPS, Raspberry Pi 3/4/5, old laptop) — ARM64 or AMD64 |
| RAM | At least 1.5–2 GB (Kubo + Cluster together use ~500 MB–1 GB idle) |
| Disk space | As much as you want to contribute, configurable via `IPFS_STORAGE_MAX` |
| Software | Docker |
| Access | The cluster secret + bootstrap address (shared privately after you sign up) |

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
CLUSTER_SECRET=<the secret the coordinator shared with you>
CLUSTER_PEERNAME=choose-a-unique-name         # e.g. "jan-vps" — for identification only
COORDINATOR_PEER_ID=12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
CLUSTER_FOLLOWERMODE=true                     # volunteer peers run in follower mode — cannot add/remove pins
IPFS_STORAGE_MAX=200GB                         # how much you want to contribute; leave empty for 4TB default
BOOTSTRAP_PEERS=/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
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

Once your peer connects, the cluster automatically assigns CIDs to it based on
the configured replication factor (currently min 2, max 2 — growing to 5 as more
volunteers join). Your node starts downloading and hosting the assigned CIDs
immediately — no manual step from the coordinator needed.

The long-term goal is **5 independent replicas per CID**: as more volunteers join,
the replication factor increases so that each artwork is stored on at least
5 different nodes. This protects against multiple simultaneous node failures.

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

**Can I review the CID list before joining?**
Yes — the curated CID list is public on [GitHub](https://github.com/rudyvdtas/ipfs-cluster-coordinator/blob/main/curated-cids.json)
and visible on the [live dashboard](https://glimmy.xyz/projects). All CIDs
are on-chain art and metadata indexed by CyberWatch·TheGuild. New CIDs are
added by the coordinator via `curated-cids.json` commits; you can watch the
repository for changes.

**Can volunteers add or remove CIDs?**
No. Volunteer peers run with `CLUSTER_FOLLOWERMODE=true`, which disables
local pin and unpin operations at the protocol level (`ipfs-cluster-ctl pin
add/rm` will return "Write operations are disabled"). The coordinator is the
only peer allowed to manage the pinset. The cluster handles all allocation
automatically and the coordinator's `curated-cids.json` + `sync-cids.sh`
workflow is the single source of truth.

## Questions?

Contact me through the usual channels.