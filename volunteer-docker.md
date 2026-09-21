# Volunteer — Volledige installatie (Docker)

Een volledig nieuwe peer opzetten via Docker, inclusief Kubo (IPFS) en IPFS Cluster.

## Wat je gaat doen

Je start twee Docker containers (Kubo + IPFS Cluster) op je eigen machine.
Die container verbindt met de bestaande cluster, krijgt een deel van de
gecurateerde CIDs toegewezen, en downloadt en host ze automatisch.

Je bent **read-only**: je kan geen CIDs toevoegen of verwijderen.

## Requirements

- Linux (VPS, Raspberry Pi 3/4/5, oud laptop) — ARM64 of AMD64
- RAM: minstens 1.5–2 GB (Kubo + Cluster samen ~500 MB–1 GB idle)
- Schijfruimte: instelbaar via `IPFS_STORAGE_MAX`
- Docker
- Cluster secret + bootstrap address (deelt de coordinator na aanmelding)

## Stap voor stap

### 1. Installeer Docker (sla over als je het al hebt)

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Clone de coordinator repository

```bash
git clone https://github.com/rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator
```

### 3. Maak je configuratiebestand

```bash
cp .env.example .env
nano .env
```

Vul de volgende velden in:

```
CLUSTER_SECRET=<the secret the coordinator shared with you>
CLUSTER_PEERNAME=choose-a-unique-name
COORDINATOR_PEER_ID=12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
CLUSTER_FOLLOWERMODE=true
IPFS_STORAGE_MAX=200GB
BOOTSTRAP_PEERS=/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
# Only needed if you are behind NAT — set to your public or Tailscale IP:
# CLUSTER_PEER_ADDRESSES=/ip4/<your-public-or-tailscale-ip>/tcp/9096
```

### 4. Open de firewall

```bash
sudo ufw allow 4001/tcp
sudo ufw allow 4001/udp
sudo ufw allow 9096/tcp  # alleen nodig achter NAT
```

### 5. Start

```bash
docker network create cluster-internal
docker compose up -d
```

### 6. Controleer de verbinding

```bash
docker exec cluster ipfs-cluster-ctl id
```

Als je een geldig peer-ID ziet, ben je verbonden.

## Wat gebeurt er nu?

Zodra de coordinator ziet dat je peer actief is, wordt de replicatiefactor
verhoogd zodat CIDs naar jouw node worden gedistribueerd. Je begint
automatisch met downloaden en hosten.

Controleer met:

```bash
docker exec cluster ipfs-cluster-ctl peers ls
docker exec cluster ipfs-cluster-ctl status
```

Live dashboard: **[https://glimmy.xyz](https://glimmy.xyz)**