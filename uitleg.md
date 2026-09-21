# Een nieuwe peer toevoegen aan de IPFS Cluster

Deze uitleg beschrijft hoe je op een andere machine een nieuwe peer
("vrijwilliger") toevoegt aan de bestaande cluster.

## Het rolmodel

De cluster kent één beheerder (de **coordinator**) en meerdere **vrijwillige peers**:

| | Coordinator | Vrijwillige peer |
|---|---|---|
| Pinset wijzigen (CIDs toevoegen/verwijderen) | ✅ Ja | ❌ Nee |
| Content opslaan (CIDs pinnen die worden toegewezen) | ✅ Ja | ✅ Ja |
| Deel uitmaken van het cluster (redundantie) | ✅ Ja | ✅ Ja |

De coordinator bepaalt welke CIDs gepind worden. Het cluster verdeelt
vervolgens **automatisch** welke peers elk CID daadwerkelijk opslaan
via de replicatiefactor. Vrijwilligers hoeven niets te kiezen — zij
ontvangen allocaties en hosten de content.

Vrijwillige peers draaien met een **trusted-peer configuratie**
(`CLUSTER_CRDT_TRUSTEDPEERS`). Hierdoor zijn pin/unpin-operaties op de
vrijwilliger lokaal uitgeschakeld. Alleen de coordinator kan de pinset
wijzigen.

## Voorwaarden (vrijwilliger)

- Docker (met Docker Compose) geïnstalleerd.
- Poort `9096/tcp` **uitgaand** open (naar de coordinator toe).
  Inkomend hoeft niet open, tenzij andere peers jouw machine als
  bootstrap willen gebruiken.
- Het `CLUSTER_SECRET` van de cluster. De coordinator deelt dit via een privékanaal.
  Deel het secret nooit in publieke issues, pull requests, logs, chat of in Git.

## Stap 1: Haal de gegevens van de coordinator op

Op de **coordinator-machine**:

```bash
docker exec cluster ipfs-cluster-ctl id
```

Noteer de peer-ID (voorbeeld):
```
<coordinator-peer-id> | hetzner-coordinator
```

Haal het publieke IP van de coordinator op:

```bash
curl -s https://ifconfig.me
```

## Stap 2: Kopieer de projectbestanden

```bash
git clone <url-van-ipfs-cluster-coordinator-repo>
cd ipfs-cluster-coordinator
```

## Stap 3: Maak het externe netwerk

```bash
docker network create cluster-internal
```

## Stap 4: Vul het `.env`-bestand in

```bash
cp .env.example .env
```

| Variabele | Waarde |
|-----------|--------|
| `CLUSTER_SECRET` | **Hetzelfde** secret als de coordinator — wordt privé gedeeld, nooit in Git of publieke kanalen |
| `COORDINATOR_PEER_ID` | Peer-ID van de coordinator |
| `COORDINATOR_PEER_ID` | Peer-ID van de coordinator — wordt gebruikt om trusted-peers configuratie in te stellen zodat alleen de coordinator de pinset kan wijzigen |
| `CLUSTER_PEERNAME` | Unieke naam voor deze peer, bijv. `peer-fra-2` |
| `BOOTSTRAP_PEERS` | `/ip4/<coordinator-ip>/tcp/9096/p2p/<coordinator-peer-id>` |

## Stap 5: Start de peer

```bash
docker compose up -d
```

## Stap 6: Controleer de verbinding

Op de nieuwe machine of de coordinator:

```bash
docker exec cluster ipfs-cluster-ctl peers ls
```

Je ziet nu zowel de coordinator als de nieuwe peer.

## Stap 7: Verifieer automatische allocatie (coordinator)

De coordinator kan een test-CID toevoegen met een replicatiefactor waarmee
dit over meerdere peers wordt verdeeld:

```bash
docker exec cluster ipfs-cluster-ctl pin add QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG --replication-min 2 --replication-max 2
docker exec cluster ipfs-cluster-ctl status
```

Beide peers zouden de pin moeten alloceren en uiteindelijk `PINNED` worden.

> **Let op:** `--replication-min 2` vereist minimaal 2 actieve peers.
> Bij slechts 1 peer actief, gebruik `--replication-min 1`.

## Problemen oplossen

| Symptoom | Oorzaak | Oplossing |
|----------|---------|-----------|
| `nc: Connection timed out` | Poort 9096/tcp niet bereikbaar | Firewall openen op coordinator |
| Cluster ziet geen andere peers | `CLUSTER_SECRET` verschilt | Zelfde secret op alle peers zetten |
| "Not enough peers to allocate CID" | Replicatiefactor hoger dan aantal peers | Lagere factor instellen |