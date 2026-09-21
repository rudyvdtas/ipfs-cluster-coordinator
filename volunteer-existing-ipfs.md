# Volunteer — IPFS node + Cluster

Voeg IPFS Cluster toe naast een **bestaande, draaiende Kubo-node**.
Je eigen IPFS-node blijft gewoon werken; de cluster gebruikt jouw Kubo-API
voor het beheren van de toegewezen CIDs.

## Architectuur

```
Jouw bestaande Kubo node
└── API op poort 5001
    └── IPFS Cluster (systemd service)
        ├── gebruikt jouw Kubo API
        ├── Cluster REST API: 9094
        └── Cluster gossip: 9096
```

**Waarom geen aparte Kubo?** Jouw bestaande node is voldoende. Follower mode
(`CLUSTER_FOLLOWERMODE=true`) voorkomt dat de cluster jouw eigen pins kan
verwijderen — de cluster kan alleen allocaties toevoegen aan de bestaande pinset.

## Requirements

- Een draaiende Kubo node (systemd, Docker, of manual)
- Extra ~100 MB RAM voor de cluster service
- Minstens 50 GB vrije schijfruimte voor cluster-allocaties
- Poort `9096` (TCP) open naar de coordinator
- `ipfs-cluster-service` en `ipfs-cluster-ctl` binaries

## Stap voor stap

### 1. Check je bestaande Kubo

```bash
ipfs id
curl http://127.0.0.1:5001/api/v0/version
```

Noteer het poortnummer (default 5001).

### 2. Download de cluster binaries

Gebruik dezelfde versie als de coordinator (check met
`docker exec cluster ipfs-cluster-service --version`):

```bash
CLUSTER_VERSION="1.1.6"
ARCH="linux-arm64"   # of linux-amd64

wget "https://dist.ipfs.tech/ipfs-cluster-service/v$CLUSTER_VERSION/ipfs-cluster-service_v$CLUSTER_VERSION_$ARCH.tar.gz"
tar -xzf "ipfs-cluster-service_v$CLUSTER_VERSION_$ARCH.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service *.tar.gz

ipfs-cluster-service --version
```

### 3. Initialiseer de cluster config

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R $USER:$USER /opt/ipfs-data/cluster
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
ipfs-cluster-service init --consensus crdt
```

### 4. Configureer de cluster peer

```bash
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

CLUSTER_SECRET="<the secret the coordinator shared with you>"
COORDINATOR_PEER_ID="12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd"
CLUSTER_PEERNAME="my-machine-name"
COORDINATOR_IP="149.210.143.16"

ipfs-cluster-service config set secret "$CLUSTER_SECRET"
ipfs-cluster-service config set peername "$CLUSTER_PEERNAME"
ipfs-cluster-service config set follower_mode true

# Wijs naar jouw Kubo API (verander poort als je een andere gebruikt)
sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5001|" service.json

# Zet REST API op plain HTTP
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# Stel bootstrap in naar de coordinator
ipfs-cluster-service config set cluster.bootstrap "[\"/ip4/$COORDINATOR_IP/tcp/9096/p2p/$COORDINATOR_PEER_ID\"]"
```

### 5. Maak een systemd service

```bash
sudo tee /etc/systemd/system/ipfs-cluster.service << 'EOF'
[Unit]
Description=IPFS Cluster peer
After=network.target

[Service]
Type=simple
User=$USER
Environment=IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
ExecStart=/usr/local/bin/ipfs-cluster-service daemon
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-cluster
```

### 6. Open de firewall en start

```bash
sudo ufw allow 9096/tcp
sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

### 7. Verifieer de verbinding

```bash
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

Je zou minstens 2 peers moeten zien: je eigen peer en de coordinator.

---

## Veelgestelde vragen

**Kan de cluster mijn eigen pins verwijderen?**
Nee, want `follower_mode=true` schakelt pinset-wijzigingen uit op dit niveau.
De cluster kan alleen allocaties toevoegen. Jouw eigen CIDs blijven onaangetast.

**Welke poort gebruikt de cluster?**
- `9096`: cluster gossip (moet open naar de coordinator)
- `9094`: cluster REST API (alleen lokaal)