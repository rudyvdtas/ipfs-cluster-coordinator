# IPFS Cluster volunteer toevoegen aan een bestaande ArtBox

Deze handleiding gaat uit van een **bestaande, werkende ArtBox** met Kubo/IPFS.
Je voegt hier IPFS Cluster als aparte volunteer-service aan toe.

## Architectuur

```
ArtBox Raspberry Pi
│
├── ipfs.service
│   └── Kubo/IPFS-node
│       ├── IPFS data
│       ├── lokale API: 5001
│       └── gateway: 8080
│
└── ipfs-cluster.service
    └── IPFS Cluster volunteer
        ├── gebruikt de lokale Kubo API
        ├── Cluster API: 9094
        └── Cluster peer communication: 9096
```

Cluster praat lokaal met de bestaande Kubo-node:

```
IPFS Cluster → http://127.0.0.1:5001 → bestaande Kubo-node
```

**Wat er niet verandert:**
- Kubo wordt niet opnieuw geïnstalleerd
- `ipfs.service` blijft ongewijzigd
- ArtBox-tools (`ipfs-tools`) blijven werken
- Er komt geen tweede IPFS-node bij

**Wat er bijkomt:**
- `ipfs-cluster-service` + `ipfs-cluster-ctl` binaries
- `ipfs-cluster.service` (systemd)
- Cluster-configuratie in een **aparte** directory

---

## Stappenplan

### 1. Bestaande Kubo-service controleren

```bash
sudo systemctl status ipfs
export IPFS_PATH=$(sudo -u ipfs ipfs config show | head -1)
echo "$IPFS_PATH"
```

Controleer welk `IPFS_PATH` ArtBox werkelijk gebruikt (meestal `/opt/ipfs-data/ipfs`).

### 2. Controleer of de Kubo API lokaal bereikbaar is

```bash
curl http://127.0.0.1:5001/api/v0/version
```

Als dit geen antwoord geeft, draait IPFS niet of is de API op een ander adres geconfigureerd:
```bash
sudo -u ipfs ipfs config Addresses.API
```

### 3. Kubo API beveiligen — mag niet publiek staan

Controleer of de API alleen op localhost luistert:

```bash
sudo -u ipfs ipfs config Addresses.API
```

Moet zijn: `/ip4/127.0.0.1/tcp/5001`

Als er een publiek IP-adres staat, wijzig naar localhost:

```bash
sudo -u ipfs ipfs config Addresses.API "/ip4/127.0.0.1/tcp/5001"
sudo systemctl restart ipfs
```

> De Cluster-service heeft alleen lokale toegang tot de API nodig. Stel 5001 nooit open naar buiten.

### 4. IPFS Cluster installeren

**Gebruik dezelfde versie als de coordinator.**
Controleer de coordinator-versie met: `docker exec cluster ipfs-cluster-service --version`

```bash
# Vervang <VERSION> met de coordinator-versie, bv. 1.0.8
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

### 5. Cluster-configuratie initialiseren in aparte directory

```bash
# Cluster-data staat naast de Kubo-data, niet erin
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster

# Initialiseer met CRDT consensus
sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt
'
```

### 6. Configuratie aanpassen

Vervang de placeholders met de echte waarden (secret en peer ID krijg je van de coordinator):

```bash
sudo -u ipfs bash -c '
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

# --- STEL HIER JE WAARDES IN ---
CLUSTER_SECRET="<HIER_JE_SECRET_INVULLEN>"
COORDINATOR_PEER_ID="<coordinator-peer-id>"
CLUSTER_PEERNAME="artbox-pi-jan"    # kies een unieke naam
COORDINATOR_IP="<coordinator-ip>"

# 1. Cluster secret
ipfs-cluster-service config set secret "${CLUSTER_SECRET}"

# 2. Peernaam
ipfs-cluster-service config set peername "${CLUSTER_PEERNAME}"

# 3. REST API via HTTP (voor lokale statuschecks)
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# 4. Bootstrap naar de coordinator
ipfs-cluster-service config set cluster.bootstrap "[
  \"/ip4/${COORDINATOR_IP}/tcp/9096/p2p/${COORDINATOR_PEER_ID}\"
]"

# 5. Follower mode (read-only — voert alleen ontvangen pinopdrachten uit)
ipfs-cluster-service config set follower_mode true
'
```

Controleer de resulterende config:

```bash
sudo cat /opt/ipfs-data/cluster/service.json | python3 -m json.tool | head -30
```

### 7. Systemd-service aanmaken

```bash
sudo tee /etc/systemd/system/ipfs-cluster.service << 'EOF'
[Unit]
Description=IPFS Cluster peer
After=network.target ipfs.service
BindsTo=ipfs.service

[Service]
Type=simple
User=ipfs
Group=ipfs
Environment=IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
Environment=IPFS_PATH=/opt/ipfs-data/ipfs
ExecStart=/usr/local/bin/ipfs-cluster-service daemon
Restart=always
RestartSec=10
LimitNOFILE=65536
MemoryHigh=512M
MemoryMax=768M

# Wacht tot IPFS API beschikbaar is
ExecStartPre=/bin/sh -c '\
  for i in $(seq 1 30); do \
    curl -s http://127.0.0.1:5001/api/v0/version >/dev/null 2>&1 && exit 0; \
    echo "Waiting for IPFS API..."; sleep 2; \
  done; \
  echo "IPFS API not ready after 60s"; exit 1'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-cluster
```

### 8. Firewall — alleen Cluster gossip openzetten

De ArtBox-firewall heeft waarschijnlijk al poort 4001 open voor Kubo. Voeg alleen Cluster-gossip toe:

```bash
# IPFS Cluster gossip (verbinding met coordinator)
sudo ufw allow 9096/tcp

# Optioneel: beperk tot alleen de coordinator
# sudo ufw allow from <coordinator-ip> to any port 9096 proto tcp

sudo ufw status verbose
```

### 9. Starten en testen

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

### 10. Status van beide services

```bash
sudo systemctl status ipfs ipfs-cluster
sudo systemctl is-enabled ipfs ipfs-cluster
```

---

## Wat er nu gebeurt

Zodra de coordinator jouw peer ziet, kun je het cluster laten uitbreiden:

1. **Coordinator verhoogt replicatie** → CIDs worden verdeeld over jouw node
2. **Jouw node begint automatisch met downloaden** van toegewezen CIDs
3. **Voortgang is te zien** op het dashboard

De ArtBox blijft gewoon zijn eigen `ipfs.service` draaien. De cluster-service is een extra laag die pinopdrachten ontvangt en uitvoert op de lokale Kubo-node.

---

## Dagelijks gebruik

```bash
# Cluster status — welke CIDs host je?
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 status

# ArtBox status
ipfs-tools status

# Logs
sudo journalctl -u ipfs -n 50 --no-pager
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

### "Cannot connect to IPFS API"
```bash
sudo systemctl status ipfs
curl http://127.0.0.1:5001/api/v0/version
```

### Peer verschijnt niet op het dashboard
```bash
sudo journalctl -u ipfs-cluster -n 100 --no-pager | grep -i error
nc -zv <coordinator-ip> 9096
```