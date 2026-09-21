# Volunteer — Cluster + Artbox

Voeg een IPFS Cluster volunteer toe aan een **bestaande ArtBox** met Kubo.
De ArtBox-eigenaar wil gegarandeerd dat eigen pins onaangetast blijven.

De oplossing is een **tweede, aparte Kubo instance** voor de cluster.
Cluster-CIDs en ArtBox-CIDs raken elkaar nooit.

## Architectuur

```
ArtBox Raspberry Pi
│
├── ipfs.service (ArtBox-Kubo)
│   └── eigenaar's private CIDs (poort 5001, IPFS_PATH=/opt/ipfs-data/ipfs)
│
├── ipfs-cluster-ipfs.service (Cluster-Kubo)
│   └── cluster-CIDs alleen (poort 5002, IPFS_PATH=/opt/ipfs-data/cluster-ipfs)
│
└── ipfs-cluster.service
    └── gebruikt Cluster-Kubo API (5002), gossip op 9096
```

De cluster praat **nooit** met de ArtBox-Kubo. Het gebruikt een eigen Kubo
op poort 5002 met een eigen peer-ID en eigen repository.

### Waarom niet de ArtBox-Kubo herbruiken?

Kubo kan geen onderscheid maken tussen een pin van de ArtBox-eigenaar en
een pin van de cluster. Als de cluster tijdens herbeweging een CID unpint,
kan dat een ArtBox-pin verwijderen. `follower_mode=true` voorkomt dit niet —
het voorkomt alleen dat de vrijwilliger zelf pinset-wijzigingen *start*.

Een aparte Cluster-Kubo is de enige garantie dat ArtBox-CIDs nooit verdwijnen.

## Requirements

| Service | RAM (idle) | RAM (actief) |
|---------|-----------|-------------|
| ArtBox-Kubo | ~200 MB | ~400 MB |
| Cluster-Kubo | ~200 MB | ~400 MB |
| IPFS Cluster | ~50 MB | ~100 MB |
| **Totaal** | **~450 MB** | **~900 MB** |

- Raspberry Pi 4 (4GB+) of beter
- Minstens 50 GB vrije schijfruimte voor cluster-CIDs
- Poorten `4002/tcp+udp` (Cluster-Kubo swarm) en `9096/tcp` (cluster gossip) open
- `ipfs-cluster-service` en `ipfs-cluster-ctl` binaries

## Stap voor stap

### 1. Check de bestaande ArtBox-Kubo

```bash
sudo systemctl status ipfs
sudo -u ipfs ipfs config Path
```

Bevestig dat het draait en noteer `IPFS_PATH` (meestal `/opt/ipfs-data/ipfs`).

### 2. Installeer een tweede Kubo (Cluster-Kubo)

Gebruik dezelfde versie als de ArtBox-Kubo:

```bash
ARTBOX_KUBO_VERSION=$(/usr/local/bin/ipfs version | cut -d' ' -f3)
echo "$ARTBOX_KUBO_VERSION"

cd /tmp
wget "https://dist.ipfs.tech/kubo/$ARTBOX_KUBO_VERSION/kubo_$ARTBOX_KUBO_VERSION\_linux-arm64.tar.gz"
tar -xzf "kubo_$ARTBOX_KUBO_VERSION\_linux-arm64.tar.gz"
cd kubo
sudo bash install.sh
cd .. && rm -rf kubo kubo_*.tar.gz
```

### 3. Initialiseer de Cluster-Kubo (aparte repo)

```bash
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster-ipfs
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs init --profile=lowpower
'
```

Dit krijgt een eigen peer-ID — normaal en verwacht.

### 4. Configureer de Cluster-Kubo

```bash
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs config Datastore.StorageMax "100GB"
  ipfs config Datastore.StorageGCWatermark 85
  ipfs config Datastore.GCPeriod "1h"
  ipfs config Routing.Type "dhtclient"
  ipfs config Reprovider.Interval "0"
  ipfs config Addresses.API "/ip4/127.0.0.1/tcp/5002"
  ipfs config Addresses.Gateway "/ip4/127.0.0.1/tcp/8081"
  ipfs config Addresses.Swarm "[\"/ip4/0.0.0.0/tcp/4002\", \"/ip6/::/tcp/4002\"]"
'
```

Let op: aparte API poort (5002), aparte swarm poort (4002).

### 5. Maak de Cluster-Kubo systemd service

```bash
sudo tee /etc/systemd/system/ipfs-cluster-ipfs.service << 'EOF'
[Unit]
Description=IPFS daemon for Cluster
After=network.target

[Service]
Type=notify
User=ipfs
Group=ipfs
Environment=IPFS_PATH=/opt/ipfs-data/cluster-ipfs
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=always
RestartSec=5
LimitNOFILE=65536
MemoryHigh=512M
MemoryMax=768M

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ipfs-cluster-ipfs
curl http://127.0.0.1:5002/api/v0/version
```

### 6. Installeer IPFS Cluster binaries

```bash
CLUSTER_VERSION="1.1.6"

cd /tmp
wget "https://dist.ipfs.tech/ipfs-cluster-service/v$CLUSTER_VERSION/ipfs-cluster-service_v$CLUSTER_VERSION\_linux-arm64.tar.gz"
tar -xzf "ipfs-cluster-service_v$CLUSTER_VERSION\_linux-arm64.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service *.tar.gz

ipfs-cluster-service --version
```

### 7. Initialiseer en configureer de cluster

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster

sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt

  CLUSTER_SECRET="<the secret the coordinator shared with you>"
  COORDINATOR_PEER_ID="12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd"
  CLUSTER_PEERNAME="artbox-pi-jan"
  COORDINATOR_IP="149.210.143.16"

  ipfs-cluster-service config set secret "$CLUSTER_SECRET"
  ipfs-cluster-service config set peername "$CLUSTER_PEERNAME"
  ipfs-cluster-service config set follower_mode true

  # Wijs naar Cluster-Kubo (poort 5002), NIET de ArtBox-Kubo
  sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5002|" service.json
  sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

  ipfs-cluster-service config set cluster.bootstrap "[\"/ip4/$COORDINATOR_IP/tcp/9096/p2p/$COORDINATOR_PEER_ID\"]"
'
```

### 8. Maak de cluster systemd service

```bash
sudo tee /etc/systemd/system/ipfs-cluster.service << 'EOF'
[Unit]
Description=IPFS Cluster peer
After=network.target ipfs-cluster-ipfs.service
BindsTo=ipfs-cluster-ipfs.service

[Service]
Type=simple
User=ipfs
Group=ipfs
Environment=IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
Environment=IPFS_PATH=/opt/ipfs-data/cluster-ipfs
ExecStart=/usr/local/bin/ipfs-cluster-service daemon
Restart=always
RestartSec=10
LimitNOFILE=65536
MemoryHigh=512M
MemoryMax=768M
ExecStartPre=/bin/sh -c '\
  for i in $(seq 1 30); do \
    curl -s http://127.0.0.1:5002/api/v0/version >/dev/null 2>&1 && exit 0; \
    echo "Waiting for Cluster-Kubo API..."; sleep 2; \
  done; \
  echo "Cluster-Kubo API not ready after 60s"; exit 1'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-cluster
```

### 9. Open de firewall en start

```bash
sudo ufw allow 4002/tcp
sudo ufw allow 4002/udp
sudo ufw allow 9096/tcp
sudo ufw status verbose

sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

### 10. Verifieer de setup

```bash
# Cluster peer ID
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id

# Verbonden peers
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls

# Alle 3 services draaien
sudo systemctl status ipfs ipfs-cluster-ipfs ipfs-cluster
```

### 11. Bevestig isolatie

```bash
# ArtBox pins — deze zouden nooit mogen veranderen door cluster activiteit
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls

# Cluster-Kubo identity (andere peer-ID dan ArtBox)
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id
```

---

## Validatie checklist

| Check | Commando |
|-------|----------|
| ArtBox-Kubo peer-ID | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs id` |
| Cluster-Kubo peer-ID | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id` |
| Cluster verbonden | `ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls` |
| ArtBox pins ongewijzigd | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls` |

Zie de volledige ArtBox-gids op `how-to-cluster-artbox.md` voor meer details
en troubleshooting.