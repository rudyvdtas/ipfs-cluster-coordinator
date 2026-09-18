# NAT / Asymmetrische Connectiviteit — Troubleshooting

## Probleem

Een volunteer-peer achter NAT (privaat IP `192.168.160.x`, Docker Desktop op macOS) kan
wél uitgaand verbinden met de coordinator (publiek IP `149.210.143.16`), maar de coordinator
kan de volunteer niet terugbereiken. De volunteer adverteert z'n Docker-bridge IP, wat vanaf
de VPS onbereikbaar is.

Hierdoor:

1. Coordinator ziet kort `Peer added <volunteer-id>` in logs
2. Coordinator kan geen metrics ophalen (`ping`, `freespace` alerts)
3. Volunteer verschijnt niet blijvend in `peers ls`
4. Coordinator rapporteert `Sees 0 other peers`

## Wat wél werkt

| Check | Status |
|-------|--------|
| `CLUSTER_CRDT_TRUSTEDPEERS=*` op coordinator | `*` actief |
| `trusted_peers` in `service.json` bevat alle 3 peer IDs | Geldig |
| Poort 9096 op VPS open (iptables + docker-proxy) | Open |
| Beide peers draaien zelfde ipfs-cluster versie (1.1.6) | Match |
| Volunteer ziet de coordinator in eigen `peers ls` | Ja |
| `pin_only_on_trusted_peers: false` | Correct |

## Wat níet werkt

De coordinator kan `192.168.160.x:9096` niet bereiken. In theorie zou libp2p de bestaande
uitgaande verbinding van de volunteer moeten hergebruiken voor bidirectioneel verkeer, maar
in de praktijk probeert ipfs-cluster een directe verbinding naar de geadverteerde adressen
te openen voor CRDT-sync en metric-collectie — en dat faalt.

## Oplossing: Tailscale

Tailscale geeft beide machines een routeerbaar IP op hetzelfde privé-netwerk (`100.x.x.x`),
zonder poorten publiek open te zetten.

1. Installeer Tailscale op VPS + Mac volunteer
2. Volunteer stelt `CLUSTER_PEER_ADDRESSES=/ip4/<tailscale-ip>/tcp/9096` in
3. Coordinator kan de volunteer nu bereiken via het Tailscale IP

Zie `volunteer_cluster.md` voor de volledige instructies voor de volunteer.

## Geprobeerde fixes (niet afdoende)

- `CLUSTER_CRDT_TRUSTEDPEERS` van `${COORDINATOR_PEER_ID}` naar `*` — nodig voor toelaten peers, maar lost NAT niet op
- `TRUSTED_PEERS` env var met comma-separated IDs in patch-script — geldige config, maar connectie blijft asymmetrisch
- Herstarten beide peers — peer verschijnt kort en verdwijnt weer