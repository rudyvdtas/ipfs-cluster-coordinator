# Getting started for volunteers

This is the clean, single path for a volunteer who joins the cluster with the standard Docker setup.

## Standard setup

1. Clone the coordinator repository.
2. Copy the example environment file.
3. Fill in the cluster secret, peer name, and coordinator peer ID.
4. Start the Docker stack.
5. Verify peer registration and cluster membership.

## Typical commands

```bash
git clone https://github.com/rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator
cp .env.example .env
```

Then fill in the required values in `.env`:

- `CLUSTER_SECRET` — shared cluster secret (zelfde op alle peers, verkrijg via de coordinator)
- `CLUSTER_PEERNAME` — unieke naam voor jouw node, bijv. `mijn-pi-thuis`
- `COORDINATOR_PEER_ID` — peer ID van de coordinator (zie `volunteer_cluster.md` of vraag op)
- `BOOTSTRAP_PEERS` — multiaddr van de coordinator om te joinen
- `IPFS_STORAGE_MAX` — hoeveel ruimte je wil vrijmaken voor IPFS-data (bv. `100GB`)

Then:

```bash
docker network create cluster-internal
# Dit gedeelde netwerk is nodig omdat de cluster container de REST API
# beschikbaar maakt voor andere containers (zoals de monitor/tracker) via
# dit netwerk. De docker-compose.yaml gebruikt een external network met
# de naam 'cluster-internal' — zonder aanmaken start de container niet.
docker compose up -d
```

Verify the peer is visible:

```bash
docker exec cluster ipfs-cluster-ctl id
docker exec cluster ipfs-cluster-ctl peers ls
```

## Normal behavior

The cluster is designed to allocate content based on free space across volunteers.

That means:
- large peers receive more pins than small peers
- peers with 0 free capacity do not receive new pins
- there is no custom per-peer override in the standard workflow

## Documentation note

This repository contains multiple older volunteer documents. This file is the single, general Docker path and intentionally does not branch into special-case scenarios.
