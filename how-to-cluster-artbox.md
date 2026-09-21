# IPFS Cluster volunteer toevoegen aan een bestaande ArtBox

Deze handleiding gaat uit van een **bestaande, werkende ArtBox** met Kubo/IPFS.
Je voegt hier IPFS Cluster als aparte volunteer-service aan toe.

**Veilige architectuur:** Cluster krijgt een **eigen, aparte Kubo-instance**. Zo blijft de
persoonlijke pinset van de ArtBox-eigenaar beschermd tegen Cluster-herverdeling of
pinsetwijzigingen.

---

## Architectuur

```
ArtBox Raspberry Pi
│
├── ipfs.service
│   └── ArtBox-Kubo (IPFS_PATH=/opt/ipfs-data/ipfs)
│       ├── privé-CIDs van de eigenaar
│       ├── API: 5001
│       └── gateway: 8080
│
├── ipfs-cluster-ipfs.service
│   └── Cluster-Kubo (IPFS_PATH=/opt/ipfs-data/cluster-ipfs)
│       ├── uitsluitend Cluster-managed CIDs
│       ├── API: 5002
│       └── gateway: 8081 (indien nodig)
│
└── ipfs-cluster.service
    └── IPFS Cluster volunteer
        ├── gebruikt de Cluster-Kubo API (5002)
        ├── Cluster API: 9094
        └── Cluster peer communication: 9096
```

IPFS Cluster praat **niet** met de ArtBox-Kubo, maar met de eigen Cluster-Kubo:

```
IPFS Cluster → http://127.0.0.1:5002 → Cluster-Kubo (aparte repository)
```

### Waarom niet de ArtBox-Kubo hergebruiken?

```
ArtBox/Kubo
└── lokale pins van de eigenaar

IPFS Cluster ──> zelfde Kubo API ──> zelfde pinset
```

Kubo maakt geen onderscheid tussen een pin van de ArtBox-eigenaar en een pin van Cluster.
Wanneer Cluster een CID uit de gedeelde pinset verwijdert (bv. bij herverdeling), kan het
een lokale ArtBox-pin unpinnen. `follower_mode=true` voorkomt dit niet — het voorkomt alleen
dat de volunteer *zelf* pinsetwijzigingen initieert.

Een aparte Cluster-Kubo is de enige garantie dat ArtBox-CIDs nooit verdwijnen door
Cluster-actie.

**Wat er niet verandert:**
- ArtBox `ipfs.service` blijft ongewijzigd
- ArtBox-tools (`ipfs-tools`) blijven werken
- ArtBox-pinset wordt nooit aangeraakt door Cluster

**Wat er bijkomt:**
- Aparte Kubo-instance voor Cluster in `/opt/ipfs-data/cluster-ipfs`
- `ipfs-cluster-ipfs.service` (systemd)
- `ipfs-cluster-service` + `ipfs-cluster-ctl` binaries
- `ipfs-cluster.service` (systemd)
- Cluster-configuratie in `/opt/ipfs-data/cluster`

**Kanttekening:** twee Kubo-daemons kosten extra geheugen (elk ~200-400 MB), CPU en
schijfruimte. Op een Raspberry Pi 4 (4GB+) is dat goed te doen, maar houd er rekening mee.

---

## Stappenplan

### 1. Bestaande ArtBox-Kubo controleren

```bash
sudo systemctl status ipfs
```

Controleer het IPFS_PATH dat ArtBox gebruikt (meestal `/opt/ipfs-data/ipfs`):

```bash
sudo -u ipfs ipfs config Path
```

### 2. Cluster-Kubo installeren

Installeer een tweede Kubo voor Cluster-gebruik. **Gebruik dezelfde versie als de
ArtBox-Kubo**, zodat het netwerkprotocol compatibel is.

```bash
# Bepaal de ArtBox-Kubo-versie
ARTBOX_KUBO_VERSION=$(/usr/local/bin/ipfs version | cut -d' ' -f3)
echo "$ARTBOX_KUBO_VERSION"

# Of stel handmatig in
ARTBOX_KUBO_VERSION="v0.35.0"

cd /tmp
wget "https://dist.ipfs.tech/kubo/${ARTBOX_KUBO_VERSION}/kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
tar -xzf "kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
cd kubo
sudo bash install.sh
cd .. && rm -rf kubo kubo_*.tar.gz
```

### 3. Cluster-Kubo initialiseren in aparte directory

```bash
# Aparte repository — niet in /opt/ipfs-data/ipfs
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster-ipfs

sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs init --profile=lowpower
'
```

Let op: de Cluster-Kubo krijgt een **eigen peer ID**. Dat is normaal — hij treedt op als
een zelfstandige IPFS-node, uitsluitend voor Cluster-verkeer.

### 4. Cluster-Kubo configureren

```bash
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs

  # Storage: Cluster-CIDs nemen ruimte in naast ArtBox-CIDs
  ipfs config Datastore.StorageMax "100GB"
  ipfs config Datastore.StorageGCWatermark 85
  ipfs config Datastore.GCPeriod "1h"
  ipfs config Routing.Type "dhtclient"
  ipfs config Reprovider.Interval "0"  # Cluster republiceert zelf niet

  # API op een andere poort dan de ArtBox-Kubo
  ipfs config Addresses.API "/ip4/127.0.0.1/tcp/5002"
  ipfs config Addresses.Gateway "/ip4/127.0.0.1/tcp/8081"

  # Swarm op een andere poort dan de ArtBox-Kubo (4001)
  ipfs config Addresses.Swarm "[\"/ip4/0.0.0.0/tcp/4002\", \"/ip6/::/tcp/4002\"]"
'
```

### 5. Cluster-Kubo systemd-service aanmaken

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
sudo systemctl enable ipfs-cluster-ipfs
sudo systemctl start ipfs-cluster-ipfs

# Controleer
sudo systemctl status ipfs-cluster-ipfs
```

Test of de API bereikbaar is:

```bash
curl http://127.0.0.1:5002/api/v0/version
```

### 6. IPFS Cluster binaries installeren

**Gebruik dezelfde versie als de coordinator.**
Controleer de coordinator-versie met: `docker exec cluster ipfs-cluster-service --version`

```bash
CLUSTER_VERSION="1.0.8"

cd /tmp
wget "https://dist.ipfs.tech/ipfs-cluster-service/v${CLUSTER_VERSION}/ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
tar -xzf "ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service ipfs-cluster-service_*.tar.gz

# Controleer
ipfs-cluster-service --version
ipfs-cluster-ctl --version
```

### 7. Cluster-configuratie initialiseren

```bash
# Aparte directory voor Cluster-config
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster

sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt
'
```

### 8. Cluster configureren

Vervang de placeholders met de echte waarden (secret en peer ID krijg je van de coordinator):

```bash
sudo -u ipfs bash -c '
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

# --- STEL HIER JE WAARDES IN ---
CLUSTER_SECRET="<HIER_JE_SECRET_INVULLEN>"
COORDINATOR_PEER_ID="<coordinator-peer-id>"
CLUSTER_PEERNAME="artbox-pi-jan"
COORDINATOR_IP="<coordinator-ip>"

# 1. Cluster secret
ipfs-cluster-service config set secret "${CLUSTER_SECRET}"

# 2. Peernaam
ipfs-cluster-service config set peername "${CLUSTER_PEERNAME}"

# 3. REST API via HTTP (voor lokale statuschecks)
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# 4. Verbind met de Cluster-Kubo (niet de ArtBox-Kubo)
sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5002|" service.json

# 5. Bootstrap naar de coordinator
ipfs-cluster-service config set cluster.bootstrap "[
  \"/ip4/${COORDINATOR_IP}/tcp/9096/p2p/${COORDINATOR_PEER_ID}\"
]"

# 6. Follower mode
ipfs-cluster-service config set follower_mode true
'
```

Controleer de resulterende config:

```bash
sudo cat /opt/ipfs-data/cluster/service.json | python3 -m json.tool | head -40
```

### 9. IPFS Cluster systemd-service aanmaken

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

# Wacht tot de Cluster-Kubo API beschikbaar is (poort 5002)
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

### 10. Firewall openzetten

De ArtBox-firewall heeft waarschijnlijk al poort 4001 open. De Cluster-Kubo gebruikt 4002
— die moet ook open voor IPFS-netwerkverkeer. Cluster-gossip (9096) moet open naar de
coordinator.

```bash
# Cluster-Kubo swarm
sudo ufw allow 4002/tcp
sudo ufw allow 4002/udp

# IPFS Cluster gossip
sudo ufw allow 9096/tcp

# Optioneel: beperk 9096 tot alleen de coordinator
# sudo ufw allow from <coordinator-ip> to any port 9096 proto tcp

sudo ufw status verbose
```

### 11. Starten en testen

```bash
# Start cluster
sudo systemctl start ipfs-cluster

# Volg de logs
sudo journalctl -u ipfs-cluster -f
```

Wacht tot de peer verbonden is, test dan:

```bash
# Check cluster peer ID
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id

# Check of je verbonden bent met de coordinator
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

Je zou **minimaal 2 peers** moeten zien: je eigen peer en de coordinator.

### 12. Status van alle services

```bash
sudo systemctl status ipfs ipfs-cluster-ipfs ipfs-cluster
sudo systemctl is-enabled ipfs ipfs-cluster-ipfs ipfs-cluster
```

---

## Wat er nu draait

| Service | Functie | IPFS_PATH | API |
|---|---|---|---|
| `ipfs.service` | ArtBox-Kubo (privé-CIDs) | `/opt/ipfs-data/ipfs` | 5001 |
| `ipfs-cluster-ipfs.service` | Cluster-Kubo (Cluster-CIDs) | `/opt/ipfs-data/cluster-ipfs` | 5002 |
| `ipfs-cluster.service` | Cluster volunteer | `/opt/ipfs-data/cluster` | 9094 |

De ArtBox-eigenaar beheert zijn eigen CIDs via poort 5001. Cluster beheert gedeelde CIDs
via de Cluster-Kubo op poort 5002. Ze kunnen elkaar niet in de weg zitten.

---

## Wat er nu gebeurt

Zodra de coordinator jouw peer ziet, kun je het cluster laten uitbreiden:

1. **Coordinator verhoogt replicatie** → CIDs worden verdeeld over jouw node
2. **Jouw Cluster-Kubo begint met downloaden** van toegewezen CIDs
3. **Voortgang is te zien** op het dashboard

De ArtBox blijft onaangeroerd — geen enkele pin van de eigenaar wordt geraakt.

---

## Resource-gebruik

Twee Kubo-daemons naast elkaar kost extra geheugen. Op een Raspberry Pi 4:

| Service | RAM (rustig) | RAM (actief) |
|---|---|---|
| ArtBox-Kubo | ~200 MB | ~400 MB |
| Cluster-Kubo | ~200 MB | ~400 MB |
| IPFS Cluster | ~50 MB | ~100 MB |
| **Totaal** | **~450 MB** | **~900 MB** |

Een 4GB Raspberry Pi heeft voldoende headroom. Bij 8GB is er geen enkel probleem.

Schijfruimte: Cluster-CIDs worden gedownload naar `/opt/ipfs-data/cluster-ipfs`. Houd
hier rekening mee bij de partitiegrootte.

---

## Dagelijks gebruik

```bash
# ArtBox status
ipfs-tools status

# Cluster status — welke CIDs host je?
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 status

# Logs
sudo journalctl -u ipfs -n 50 --no-pager
sudo journalctl -u ipfs-cluster-ipfs -n 50 --no-pager
sudo journalctl -u ipfs-cluster -n 50 --no-pager
```

---

## Troubleshooting

### Cluster start niet: "secret mismatch"
```bash
sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service config set secret "<CORRECTE_SECRET>"
'
sudo systemctl restart ipfs-cluster
```

### Cluster-Kubo API niet bereikbaar
```bash
sudo systemctl status ipfs-cluster-ipfs
curl http://127.0.0.1:5002/api/v0/version
```

Als de Cluster-Kubo niet draait: `sudo systemctl restart ipfs-cluster-ipfs`

### Peer verschijnt niet op het dashboard
```bash
sudo journalctl -u ipfs-cluster -n 100 --no-pager | grep -i error
nc -zv <coordinator-ip> 9096
```

### ArtBox-Kubo en Cluster-Kubo swarm poorten
Controleer of beide poorten open zijn:

```bash
sudo ufw status | grep -E '4001|4002'
ss -tuln | grep -E '4001|4002'
```