# Vrijwilliger worden — IPFS Cluster · CyberWatch · TheGuild

Bedankt dat je wilt deelnemen! Met deze stappen word je onderdeel van het
cluster en host je automatisch een deel van de geselecteerde content.

## Wat je nodig hebt

- Een Linux-machine (VPS, Raspberry Pi 3/4/5, oude laptop — ARM64 of AMD64)
  `ipfs/kubo` en `ipfs/ipfs-cluster` zijn **multi-arch** images, Docker trekt
  automatisch de juiste versie voor jouw architectuur.
- **Minimaal 1.5–2GB RAM** (Kubo + Cluster samen verbruiken ~500MB–1GB idle)
- **Zoveel vrije schijfruimte als je wilt bijdragen**, stel je in via `IPFS_STORAGE_MAX`
- Docker geïnstalleerd (`curl -fsSL https://get.docker.com | sh`)
- Het cluster-secret (deel ik privé)

## Bootstrap je peer

```bash
git clone git@github.com:rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator
cp .env.example .env
nano .env
```

Vul in `.env` in:

```
CLUSTER_SECRET=<jouw-secret>
CLUSTER_PEERNAME=kies-een-unieke-naam
COORDINATOR_PEER_ID=12D3KooWSwQrE3YTewpixUEYxLBd6pBQCDyDposciqtXNHPTaTsz
# Zoveel GB als je wilt bijdragen, bijv. 50GB, 200GB, 400GB — of leeg voor 4TB default
IPFS_STORAGE_MAX=200GB
BOOTSTRAP_PEERS=/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWSwQrE3YTewpixUEYxLBd6pBQCDyDposciqtXNHPTaTsz
```

```bash
docker network create cluster-internal
ufw allow 4001/tcp 4001/udp
docker compose up -d
docker exec cluster ipfs-cluster-ctl id   # check of je verbonden bent
```

## Wat er gebeurt

- Je IPFS-node host een deel van de 110+ geselecteerde CIDs
- Het cluster verdeelt automatisch **wie welke CID opslaat** (allocatie)
- Je kunt alleen **lezen en repliceren** — niet zelf CIDs toevoegen/verwijderen
- Data wordt gestreamd via IPFS; je hoeft zelf geen bronbestanden te beheren

## Na je toetreding (coordinator)

Zodra je als peer zichtbaar bent, update ik de replicatiefactor zodat
alle CIDs over beide peers worden verdeeld (redundantie). Vanaf dat
moment staat elke CID op minimaal 2 peers (jij + de coordinator).

## Verifiëren

```bash
docker exec cluster ipfs-cluster-ctl peers ls         # zie de coordinator + andere peers
docker exec cluster ipfs-cluster-ctl status            # status van alle gepinde CIDs
```

Het dashboard met de actuele status staat op:
**[https://glimmy.xyz](https://glimmy.xyz)**

## Vragen?

Neem contact op via de gebruikelijke kanalen.