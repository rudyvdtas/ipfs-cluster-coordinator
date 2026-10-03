# IPFS Cluster — CyberWatch · TheGuild

## Wat we hebben

### Infrastructuur

| Component | Locatie | Status |
|-----------|---------|--------|
| VPS | Productie-VPS | ✅ Draait |
| SSH | Productiehost — wordt privé beheerd, niet hier gedocumenteerd | ✅ |
| Deployment | 2 services: `ipfs-cluster-coordinator` (cluster) + `sveltekit-monitor-app` (monitor) | ✅ Gedeployed |
| IPFS (Kubo) | Docker, container `ipfs`, vanuit `ipfs-cluster-coordinator/docker-compose.yaml` | ✅ Healthy |
| Cluster peer | Docker, container `cluster`, vanuit `ipfs-cluster-coordinator/docker-compose.yaml` | ✅ Draait |
| Dashboard (SvelteKit) | Docker, container `cluster-dashboard`, vanuit `sveltekit-monitor-app/docker-compose.yaml` | ✅ Read-only, toont cluster data |
| Caddy reverse proxy | VPS host, poort 80 → 443 → 3000 | ✅ HTTPS |
| Git repos | GitHub `rudyvdtas/ipfs-cluster-coordinator` + `rudyvdtas/sveltekit-monitor-app` | ✅ Gepusht |

### Deployment architectuur

**Cluster en monitor zijn bewust apart gehouden.** Ze hebben elk hun eigen functie
en moeten onafhankelijk kunnen schalen en deployen:

- `ipfs-cluster-coordinator`: beheert het IPFS cluster — Kubo node, cluster peer, pins, CID sync, vrijwilligers
- `sveltekit-monitor-app`: monitort het cluster — read-only dashboard, toont peers, pin status, redundancy

Beide services delen het `cluster-internal` Docker netwerk (`external: true`) zodat
de dashboard container de cluster REST API kan bereiken. De communicatie loopt via
`http://cluster:9094` (CLUSTER_API_URL in dashboard Dockerfile).

**Let op — DNS-limiet bij aparte compose stacks:** Wanneer services in aparte compose
stacks draaien, resolved Docker DNS service namen (`cluster`) alleen
binnen dezelfde stack. Fallback: zet `CLUSTER_API_URL` op het interne netwerk-IP
van de cluster container. Een network alias op het gedeelde Docker netwerk
lost dit op (mits de deployment tool het niet strip):

### Functionaliteit

- 105 van 110 CIDs gepind in de cluster (5 errors onbekend)
- Coordinator/vrijwilliger rollenscheiding via `CLUSTER_CRDT_TRUSTEDPEERS=${COORDINATOR_PEER_ID}` (alleen coordinator produceert pinset-operaties) + `trusted_peers` / `pin_only_on_trusted_peers` op vrijwilligers
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

3. **Dashboard → cluster DNS** — container namen kunnen willekeurig zijn
   (bv. bij sommige deployment tools), Docker DNS over
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

### 5. JSON config patchen met sed range is bros

`sed` range patronen op JSON config zijn breekbaar: na de eerste patch staat de config
op 1 regel → de sed range matcht onbedoeld verder in het bestand. **Vervangen door awk.**

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

### 9. SSH-toegang

Toegang tot de productiehost wordt privé beheerd en is niet onderdeel van
deze publieke documentatie.

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

### 12. Docker DNS werkt niet over aparte compose stacks heen

Sommige deployment tools negeren `container_name` en genereren eigen container namen.
Omdat services in **aparte** compose stacks kunnen draaien (andere `--project-name`),
resolved Docker's interne DNS service-namen (`cluster`) niet in de andere stack.

**Network alias werkt wel (mits de tool het niet strip):**
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

1. ~~SSH-toegang productiehost~~ ✅
2. Eerste vrijwilliger onboarden (via `volunteer_cluster.md`)
3. Replicatie updaten naar min=2 na 2e peer (`scripts/sync-cids.sh 2 2`)
4. Nog 5 CIDs onderzoeken bij sync (fouten)
5. Opschalen VPS als er meer peers/opslag nodig is

## Laatste sessie — 18 Sep 2026

### 15. Container-naam verandert bij elke deploy

Sommige deployment tools genereren een nieuw suffix voor de container-naam bij elke
deploy of herstart. `container_name` in docker-compose wordt soms genegeerd.
Gebruik een dynamische lookup:

```bash
NAME=$(docker ps --format '{{.Names}}' | grep -i cluster)
docker exec $NAME ipfs-cluster-ctl ...
```

### 16. Coordinator peer ID opvragen

```bash
docker exec <container-name> ipfs-cluster-ctl id
```

### 17. CIDs pinnen vanaf de VPS

De repo moet op de VPS staan (`git clone` in `/opt`). Gebruik `scripts/sync-cids.sh`
vanuit die directory om CIDs te pinnen.

### 18. Coordinator-only pinset via CRDT_TRUSTEDPEERS

`CLUSTER_CRDT_TRUSTEDPEERS=${COORDINATOR_PEER_ID}` in docker-compose zorgt dat
alleen de coordinator CRDT pinset-operaties produceert. Vrijwilligers ontvangen
en passen de updates toe maar kunnen zelf geen pinset-wijzigingen initiëren.
`trusted_peers` + `pin_only_on_trusted_peers` op vrijwilligers is een extra lokale beveiligingslaag.
Vrijwilligers hebben alleen nodig:

- `CLUSTER_SECRET` — hex string uit `service.json`
- Bootstrap multiaddress met coordinator peer ID: `/ip4/<coordinator-ip>/tcp/9096/p2p/<coordinator-peer-id>`

### 19. volunteer_cluster.md moet actuele peer ID bevatten

De voorbeeld peer IDs in `volunteer_cluster.md` waren oude dummy waarden.
Deze zijn vervangen door de echte coordinator peer ID, zodat
vrijwilligers het bestand letterlijk kunnen volgen zonder dat de coordinator
handmatig het juiste ID moet doorgeven.

> De peer ID in `volunteer_cluster.md` is bewust publiek — deze is nodig om
> te bootstrappen en vormt geen beveiligingsrisico zonder de bijbehorende
> `CLUSTER_SECRET`.

## Migratie weg van Coolify (okt 2026) — in uitvoering

**Aanleiding:** VPS heeft maar 1.8GB RAM. `docker stats` liet zien dat Coolify's
eigen beheerstack (sentinel + coolify + db + redis + realtime + proxy) ~424MB
gebruikte — bijna evenveel als de hele cluster-workload (`cluster` + `ipfs`
samen ~422MB). Gecombineerd met het ontbreken van memory-limits op alle
containers en een ongecontroleerde rebalance van 3336 nieuwe CIDs is dit een
belangrijke oorzaak van de VPS-crashes. Volledig plan: zie `TODO.md` in de
workspace-root.

**Branch:** `architecture-moving-away-from-coolify`

**Fase 1 (afgerond, 3 okt 2026):** Caddy 2.11.7 geïnstalleerd op de VPS, gestopt +
disabled na installatie (nooit actief geweest op 80/443, geen conflict met
`coolify-proxy`). Caddyfile met het echte domein (`glimmy.xyz` / `www.glimmy.xyz`,
ontdekt via `docker inspect` op de dashboard-labels) staat op `/etc/caddy/Caddyfile`
en is gevalideerd ("Valid configuration"). Bijvangst: `coolify-proxy` is zelf al
Caddy (caddy-docker-proxy labels), niet Traefik — de Traefik-labels in de
monitor-compose zijn dode config.

**Fase 2 (afgerond, 3 okt 2026):** `cluster` + `ipfs` losgekoppeld van Coolify,
draaien nu via plain `docker compose` vanuit `/opt/ipfs-cluster-coordinator` op de VPS.

- Ontdekt: er bestonden al **lege** volumes (`ipfs-cluster-coordinator_cluster_data`,
  `ipfs-cluster-coordinator_ipfs_data`, aangemaakt 2 okt) van een eerdere losse
  `docker compose up`-poging in dezelfde map — deze zijn bewust **niet** gebruikt
  (geen `identity.json` erin, dus geen live data).
- De echte, live data stond in Coolify's eigen volumes
  (`koaxw04zgtze4rjo16frrlbc_cluster-data` / `_ipfs-data`, aangemaakt 18 sep).
  Een `docker-compose.override.yml` (niet gecommit, host-specifiek, zie `.gitignore`)
  koppelt de service-volumes expliciet aan die bestaande volumes via
  `external: true` + `!override` merge-tag (nodig omdat de basis-`docker-compose.yaml`
  `driver: local` specificeert, wat botst met `external` zonder de merge-tag).
- `.env` aangemaakt met de echte productie-waarden (peername, secret, coordinator
  peer-ID), rechtstreeks uitgelezen uit de draaiende Coolify-container, nooit
  opnieuw in logs/output getoond.
- Cutover: oude Coolify-containers gestopt (niet verwijderd, voor rollback) →
  nieuwe stack gestart op dezelfde volumes. Geverifieerd: identieke cluster- en
  IPFS-peer-ID, pinset intact, alle 4 vrijwilligers automatisch weer verbonden,
  dashboard + tracker herstelden vanzelf na de korte cutover-downtime.
- `coolify-proxy`, `coolify`, etc. draaien nog gewoon door — worden pas in
  Fase 5 verwijderd, na een stabiliteitsperiode.

**Belangrijke ontdekking tijdens Fase 3/4 (bevestigt de oorspronkelijke crash-analyse):**
De cluster REST API antwoordt op `/pins` met een **31MB JSON-respons** (3336+ CIDs,
elk met peer-allocaties). Een los request duurt ~4-5s — niet erg. Maar tijdens het
verifiëren vielen drie zware requests toevallig samen (eigen diagnose-commando's +
de tracker's reguliere 60s-poll), en toen duurde één van die requests >35s en liep
de monitor in een timeout (`CLUSTER_TIMEOUT_MS=30000`). Zodra de gelijktijdige
requests voorbij waren, werkte alles weer meteen. **Dit bevestigt letterlijk de
oorspronkelijke hypothese: meerdere gelijktijdige zware `/pins`-aanroepen (monitor +
tracker + handmatige diagnose/rebalance) kunnen elkaar blokkeren en tijdelijk een
"cluster unavailable"-beeld geven, zonder dat er iets kapot is.** Toekomstige fix-
richting (niet nu uitgevoerd): gedeelde rate-limiting/caching tussen monitor én
tracker, of een lichtere `/pins`-variant i.p.v. de volledige payload bij elke poll.

**Fase 3 (afgerond, 3 okt 2026) — andere aanpak dan origineel gepland:** in plaats
van Docker is gekozen voor **direct Node.js + systemd** voor de monitor (zie
`sveltekit-monitor-app/LESSONS.md` voor de volledige redenering en stappen).
Hiervoor was een extra wijziging nodig: de cluster REST API (`9094`) is nu ook
gebonden aan `127.0.0.1` op de host (naast het interne `cluster-internal`
Docker-netwerk), zodat een host-level proces er zonder Docker-DNS bij kan —
nooit publiek, alleen loopback.

**Fase 4 (afgerond, 3 okt 2026):** `coolify-proxy` gestopt, standalone Caddy
gestart op 80/443. `https://glimmy.xyz` en `https://www.glimmy.xyz` geverifieerd
met geldig Let's Encrypt-certificaat en echte clusterdata. Downtime tijdens de
cutover: enkele minuten (de tijd tussen het stoppen van de oude dashboard-container
en het live zetten van Caddy + de systemd-monitor).

**Fase 5 (afgerond, 3 okt 2026):** Coolify volledig verwijderd (containers, eigen
volumes, `/data/coolify`) — vervroegd op expliciet verzoek, i.p.v. de geadviseerde
24-48u stabiliteitsperiode. Health-checks waren groen vlak voor uitvoering.
Geverifieerd met een echte VPS-reboot: `cluster`/`ipfs`/`tracker` (Docker
`restart: unless-stopped`) en `caddy`/`sveltekit-monitor` (systemd `enabled`)
kwamen allebei automatisch terug, site direct bereikbaar met volledige clusterdata.

**Resultaat:** beschikbaar geheugen 538Mi → 643Mi → **802Mi**, swap-gebruik
215Mi → 332Mi → **107Mi**. Coolify-migratie hiermee volledig afgerond.

## ⚠️ Op te pakken NA volledige afronding van de Coolify-migratie: `/pins` schaalt niet

**Status: nog niet opgelost — bewust uitgesteld tot Fase 5-7 van de Coolify-migratie
klaar zijn.** Dit is een apart, structureel probleem, losstaand van Coolify/Docker/
systemd — het bestond al daarvoor en wordt alleen maar erger naarmate de pinset groeit.

**Bevinding (3 okt 2026, live gereproduceerd):** `GET /pins` doet géén lokale lookup,
maar een **synchrone broadcast naar alle peers** (`PinTracker.StatusAll`) om van elke
peer — inclusief externe vrijwilligers over het internet — de actuele pin-status op
te halen, en wacht op alle antwoorden voor de respons wordt samengesteld. Met 3336+
CIDs en meerdere (soms trage/NAT'te) externe peers duurt die ronde regelmatig langer
dan de 30s-timeout van zowel de monitor als de tracker:

```
ERROR cluster  PinTracker.StatusAll aborted: context canceled
ERROR cluster  error in broadcast response from <peer-id>: context canceled
ERROR restapi  sending error response: 500: context canceled
```

Gemeten: payload groeide van 31MB → 38MB binnen hetzelfde uur (pinset groeit nog
steeds). Eén poging lukte in 21s, andere overschreden de 30s-timeout en kregen een
HTTP 500. **Zowel de monitor als de tracker ondervinden dit onafhankelijk van elkaar**
— dit is dus niet opgelost door de Coolify-migratie en zal bij een nog grotere pinset
(richting de resterende CIDs die nog ge-upload moeten worden) alleen maar vaker
voorkomen.

**Te onderzoeken zodra de Coolify-migratie (Fase 5-7) is afgerond:**
- Bestaat er een `?local=true`-achtige query-parameter op `/pins` of `/pins/{cid}`
  die de cluster-wide broadcast overslaat en alleen lokaal bekende status teruggeeft?
- Kan de monitor/tracker volstaan met een lichtere endpoint (bv. alleen CID-lijst +
  lokale status) in plaats van de volledige cross-peer statusronde bij elke poll?
- Gedeelde rate-limiting/caching tussen monitor én tracker, zodat niet twee
  onafhankelijke processen elk hun eigen volledige broadcast-ronde triggeren.
- Eventueel de timeout verhogen als tijdelijke lapmiddel — lost de onderliggende
  schaalbaarheid niet op, maar kan acute 500's verminderen.