# IPFS Cluster — CyberWatch · TheGuild

## Wat we hebben

### Infrastructuur

| Component | Locatie | Status |
|-----------|---------|--------|
| VPS | Eigen VPS, 149.210.143.16, via Coolify | ✅ Draait |
| Coolify | 1 project, 2 services: `ipfs-cluster-coordinator` (cluster) + `sveltekit-monitor-app` (monitor) | ✅ Gedeployed |
| IPFS (Kubo) | Docker, container `ipfs`, vanuit `ipfs-cluster-coordinator/docker-compose.yaml` | ✅ Healthy |
| Cluster peer | Docker, container `cluster`, vanuit `ipfs-cluster-coordinator/docker-compose.yaml` | ✅ Draait, peer-ID `12D3KooWSw...` |
| Dashboard (SvelteKit) | Docker, container `cluster-dashboard`, vanuit `sveltekit-monitor-app/docker-compose.yaml` | ✅ Read-only, toont cluster data |
| Caddy reverse proxy | VPS host, poort 80 → 443 → 3000 | ✅ HTTPS via Let's Encrypt |
| Git repos | GitHub `rudyvdtas/ipfs-cluster-coordinator` + `rudyvdtas/sveltekit-monitor-app` | ✅ Gepusht |

### Deployment architectuur

**Cluster en monitor zijn bewust apart gehouden.** Ze hebben elk hun eigen functie
en moeten onafhankelijk kunnen schalen en deployen:

- `ipfs-cluster-coordinator`: beheert het IPFS cluster — Kubo node, cluster peer, pins, CID sync, vrijwilligers
- `sveltekit-monitor-app`: monitort het cluster — read-only dashboard, toont peers, pin status, redundancy

Beide services delen het `cluster-internal` Docker netwerk (`external: true`) zodat
de dashboard container de cluster REST API kan bereiken. De communicatie loopt via
`http://cluster:9094` (CLUSTER_API_URL in dashboard Dockerfile).

**Let op — Coolify DNS-limiet:** Coolify negeert `container_name` en deployed beide
services als aparte compose stacks. Docker DNS resolved service namen (`cluster`) alleen
binnen dezelfde stack. Fallback: zet `CLUSTER_API_URL` in Coolify op het IP van de
cluster container op het `cluster-internal` netwerk.

### Functionaliteit

- 105 van 110 CIDs gepind in de cluster (5 errors onbekend)
- Coordinator/vrijwilliger rollenscheiding via `CLUSTER_CRDT_TRUSTEDPEERS`
- Dashboard toont peers, pin-status per CID, toggle CID lijst
- REST API op intern netwerk `cluster-internal` (niet publiek)
- Sync-script in repo (`scripts/sync-cids.sh`) om CID lijst te laden
- DHCP secret, storage limit (`4TB` → `60GB`), plain HTTP REST API via `/http` suffix
- Toekomstige vrijwilligers krijgen instructies via `volunteer_cluster.md`

## Huidig probleem (opgelost ✅ — 18 Sep 2026)

**Cluster draait, monitor toont cluster data.**

De oplossing bestond uit drie stappen:

1. **Cluster container crashte met exit code 126** — de custom `entrypoint`/`command`
   in docker-compose overschreef het image met `su-exec` en `/sbin/tini` die niet meer
   bestaan in de nieuwere `ipfs/ipfs-cluster:latest` image. Oplossing: `command` directive
   volledig verwijderen, image z'n default `daemon` command laten gebruiken.

2. **REST API luisterde op 127.0.0.1:9094 ipv 0.0.0.0:9094** — de default config
   bindt alleen aan localhost. Oplossing: handmatig `sed` op `/data/ipfs-cluster/service.json`:
   ```
   sed -i 's|/ip4/127.0.0.1/tcp/9094|/ip4/0.0.0.0/tcp/9094|' service.json
   ```

3. **Dashboard → cluster DNS** — Coolify container namen zijn random, Docker DNS over
   stacks heen is onbetrouwbaar. Uiteindelijk werkte de `cluster-internal` netwerk alias
   (`aliases: cluster`) wel, waardoor `http://cluster:9094` resolved vanuit de dashboard
   container.

## Wat we hebben geleerd

### 1. REST API heeft `/http` suffix nodig voor plain HTTP

De env var `CLUSTER_RESTAPI_HTTP_LISTEN_MULTIADDRESS` werkt niet bij bestaande volumes.
De default `http_listen_multiaddress: /ip4/127.0.0.1/tcp/9094` gebruikt libp2p-http i.p.v.
plain HTTP. Oplossing: in de entrypoint `sed -i 's|/ip4/127.0.0.1/tcp/9094|/ip4/0.0.0.0/tcp/9094/http|'`
Het `/http` suffix is essentieel.

### 2. Env vars worden niet allemaal door init gerespecteerd

`CLUSTER_SECRET` en `CLUSTER_PEERNAME` werken. `CLUSTER_CRDT_TRUSTEDPEERS` werkt als env var
tijdens init, maar een patch-script op de entrypoint is nodig voor herhaalbare boot.
De `CLUSTER_RESTAPI_*` env vars worden **niet** door init toegepast — daarom het `sed` in de entrypoint.

### 3. YAML aliases in networks sectie

Het object-formaat (`networks: default: {} cluster-internal: aliases: cluster`) i.p.v.
het lijst-formaat (`networks: - default - cluster-internal`). Het lijst-formaat met een
object als tweede item wordt niet door docker-compose geaccepteerd.

### 4. Chown ipfs:ipfs mislukt

De gebruikersgroep heet `users` (gid 100), niet `ipfs`. Gebruik `chown ipfs` (zonder :groep)
of `chown ipfs:users` / `chown 1000:100`.

### 5. YAML sed range patroon is bros

`sed -i "/\"trusted_peers\": \[/,/],/c ..."` werkt alleen de eerste keer (wanneer `trusted_peers`
pretty-printed is over 3 regels). Na de eerste patch staat het op 1 regel → de sed range
matcht onbedoeld verder in het bestand en verwijdert het `api`-gedeelte. **Vervangen door awk.**

### 6. NDJSON van /pins endpoint

Met 1 pin returned `GET /pins` een enkel JSON-object. Met 100+ pins returned het NDJSON
(elke regel een object). De frontend code moet beide formaten aankunnen.

### 7. Dashboard read-only

Publieke pin toevoegen/verwijderen is een beveiligingslek omdat de REST API geen auth heeft
(`basic_auth_credentials: null`). De coordinator schrijft pins; vrijwilligers lezen/hosten.
Git-based CID management (`curated-cids.json` + sync script) is veiliger dan een admin
paneel.

### 8. DNS propogatie

Na het zetten van het A-record duurde het enige tijd voordat DNS overal bijgewerkt was.
De laptop met Google DNS (8.8.8.8) zag het direct; andere apparaten hadden vertraging.

### 9. SSH-sleutel

De VPS accepteert alleen publickey-auth. Instellen van de lokale SSH-sleutel in
`.ssh/authorized_keys` op de VPS is nodig om zonder wachtwoord via de Mac te kunnen
SSH'en.

### 10. Colima op Mac

Lokale ontwikkeling werkt via Colima, maar productie moet op een echte server.
Colima containers zijn niet publiek bereikbaar via NAT.

### 11. Cluster en monitor hebben elk hun eigen functie — houd ze apart

De cluster en de monitor zijn aparte concerns en moeten onafhankelijk blijven:

- **Cluster** (`ipfs-cluster-coordinator`): beheert IPFS nodes, pins, CID sync,
  vrijwilligers. Moet groeien met meer peers en CIDs, onafhankelijk van de monitor.
- **Monitor** (`sveltekit-monitor-app`): read-only dashboard dat het cluster observeert.
  Toont peer status, pin distributie, redundancy. Puur een observatietool.

**Voordelen van apart houden:**
- Onafhankelijke deploys — dashboard update herstart de cluster niet
- Geen code duplicatie — elk repo is eigen source of truth
- Separation of concerns — cluster repo doet clusterdingen, monitor repo doet monitordingen
- Schaalbaar — dashboard kan later op een andere host draaien
- Vrijwilligers hoeven alleen de coordinator repo te clonen, niet de monitor

**Belangrijk inzicht:** verleiding is groot om alles in 1 docker-compose te gooien
"zodat DNS werkt", maar dat creëert technische schuld en koppelt dingen die los horen.
Het DNS-probleem is een netwerkconfiguratie-issue, geen architectuur-issue.

### 12. Coolify: Docker DNS werkt niet over compose stacks heen

Coolify negeert `container_name` in docker-compose en genereert eigen container namen.
Omdat beide services in **aparte** compose stacks draaien (andere `--project-name`),
resolved Docker's interne DNS service-namen (`cluster`) niet in de andere stack.

**Network alias werkt wél (mits Coolify het niet stript):**
```yaml
# in cluster docker-compose
networks:
  cluster-internal:
    aliases:
      - cluster
```
Docker's embedded DNS registreert aliases op user-defined networks en maakt ze
beschikbaar voor ALLE containers op dat netwerk, ongeacht de compose stack.

### 13. ipfs-cluster image: pas op met custom entrypoint/command

Het `ipfs/ipfs-cluster:latest` image gebruikt `tini` als entrypoint die `command`
doorgeeft als argumenten aan `ipfs-cluster-service`. Een `command: /pad/naar/script`
wordt dus behandeld als subcommand (`ipfs-cluster-service /pad/naar/script`) en
resulteert in de help output + exit.

**Oplossing:** gebruik het image z'n default `CMD ["daemon"]` — geen custom
`command` of `entrypoint` nodig. Init en config-patches kunnen als losse stap
na het starten van de container worden uitgevoerd via `docker exec`.

### 14. REST API bindt standaard aan 127.0.0.1

De default `ipfs-cluster-service init` zet `http_listen_multiaddress` op
`/ip4/127.0.0.1/tcp/9094`. Dit betekent dat de REST API alleen binnen de container
bereikbaar is — andere containers op hetzelfde Docker netwerk kunnen er niet bij.

**Fix:** pas `service.json` aan naar `/ip4/0.0.0.0/tcp/9094`. Het `patch-cluster-config.sh`
script doet dit, maar moet handmatig of via een startup hook worden uitgevoerd na elke
verse init (bij nieuwe volumes of na `ipfs-cluster-service init`).

Het `/http` suffix uit les #1 is NIET meer nodig — de nieuwere image versie gebruikt
standaard plain HTTP op poort 9094.

## Volgende stappen (kort)

1. ~~SSH-sleutel installeren op VPS (voor Mac-terminal toegang)~~ ✅
2. Eerste vrijwilliger onboarden (via `volunteer_cluster.md`)
3. Replicatie updaten naar min=2 na 2e peer (`scripts/sync-cids.sh 2 2`)
4. Nog 5 CIDs onderzoeken bij sync (fouten)
5. Opschalen VPS als er meer peers/opslag nodig is

## Laatste sessie — 18 Sep 2026

### 15. Coolify container-naam verandert bij elke deploy

Coolify genereert een nieuw suffix voor de container-naam bij elke deploy of herstart.
`container_name` in docker-compose wordt genegeerd. Gebruik altijd een dynamische lookup:

```bash
NAME=$(docker ps --format '{{.Names}}' | grep -i cluster)
docker exec $NAME ipfs-cluster-ctl ...
```

De container-naam van de coordinator was eerst `cluster-koaxw04zgtze4rjo16frrlbc-181243494596`
en later `cluster-koaxw04zgtze4rjo16frrlbc-192817309819`.

### 16. CLUSTER_SECRET & COORDINATOR_PEER_ID ophalen op de VPS

```bash
# Secret
NAME=$(docker ps --format '{{.Names}}' | grep -i cluster)
docker exec $NAME grep '"secret"' /data/ipfs-cluster/service.json

# Peer ID
docker exec $NAME ipfs-cluster-ctl id
```

Coordinator peer ID: `12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd`

### 17. CIDs pinnen vanaf de VPS

De repo moet op de VPS staan (`git clone` in `/opt`). Vanuit die directory:

```bash
NAME=$(docker ps --format '{{.Names}}' | grep -i cluster)
python3 -c "
import json
with open('curated-cids.json') as f:
    cids = json.load(f)
for c in cids:
    print(c)
" | while read cid; do
  docker exec $NAME ipfs-cluster-ctl pin add "$cid" --replication-min 1 --replication-max 1
done
```

### 18. Vrijwilligers onboarden zonder handmatige whitelist

Met `CLUSTER_CRDT_TRUSTEDPEERS=*` in docker-compose (huidige setup) kunnen vrijwilligers
zichzelf aanmelden zonder dat de coordinator ze handmatig hoeft toe te voegen. Ze hebben
alleen nodig:

- `CLUSTER_SECRET` — hex string uit `service.json`
- Bootstrap multiaddress met coordinator peer ID: `/ip4/149.210.143.16/tcp/9096/p2p/12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd`

De `TRUSTED_PEERS` env var in Coolify wordt niet automatisch toegepast — het
`patch-cluster-config.sh` script is alleen als volume gemount, niet als startup command.
En `CLUSTER_CRDT_TRUSTEDPEERS=*` overschrijft `trusted_peers` uit `service.json`.

### 19. volunteer_cluster.md moet actuele peer ID bevatten

De voorbeeld peer IDs in `volunteer_cluster.md` waren oude dummy waarden
(`12D3KooWHFTW...`). Deze zijn vervangen door de echte coordinator peer ID, zodat
vrijwilligers het bestand letterlijk kunnen volgen zonder dat de coordinator
handmatig het juiste ID moet doorgeven.