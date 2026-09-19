# Vernis ArtBox + CyberWatch Cluster — Raspberry Pi Setup

Deze handleiding installeert een volledige **Vernis ArtBox** (IPFS node + NFT tools) op
een Raspberry Pi 4 en voegt daar een **IPFS Cluster volunteer peer** aan toe die
verbinding maakt met de CyberWatch coordinator.

Na deze setup:
- draait je Pi een standalone IPFS node (Kubo) met SSD-optimalisatie
- heb je de ArtBox `ipfs-tools` CLI voor NFT-downloads, backups en health checks
- is je Pi een **read-only volunteer** in het CyberWatch cluster
- worden de 111+ curated CIDs automatisch verdeeld en gehost

---

## Vereisten

| Wat | Detail |
|---|---|
| Hardware | Raspberry Pi 4 (4GB of 8GB) — ARM64 |
| Opslag | SSD via USB, minimaal 128GB (1TB aanbevolen) |
| OS | Raspberry Pi OS 64-bit (Bookworm) |
| Netwerk | LAN of WiFi met internettoegang |
| Poorten | **4001** (TCP+UDP), **9096** (TCP) moeten open zijn in je router/firewall |
| Cluster secret | Krijg je privé van de coordinator |

---

## Deel 1 — ArtBox installeren (IPFS node)

### 1.1 Raspberry Pi OS voorbereiden

```bash
# Update het systeem
sudo apt update && sudo apt upgrade -y

# Installeer basisafhankelijkheden
sudo apt install -y curl wget tar python3 python3-pip python3-venv jq ufw smartmontools

# Optioneel: wijzig hostname
sudo hostnamectl set-hostname artbox
```

### 1.2 SSH inschakelen (als dat nog niet is gebeurd)

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

### 1.3 SSD voorbereiden

Sluit de SSD aan via USB. Controleer de device-naam:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

Je SSD verschijnt waarschijnlijk als `/dev/sda`. **Als er al data op staat die je wilt
bewaren, sla deze stap over.** Anders:

```bash
# Formatteer als ext4 (let op: dit wist alle data op de SSD)
sudo mkfs.ext4 -F /dev/sda1   # of /dev/sda als er geen partitie is
```

Maak de mount-directory en voeg toe aan fstab:

```bash
sudo mkdir -p /opt/ipfs-data

# Vind de UUID van de SSD
sudo blkid /dev/sda1   # of /dev/sda

# Voeg toe aan /etc/fstab (vervang <UUID> met de echte waarde)
echo 'UUID=<UUID> /opt/ipfs-data ext4 defaults,noatime,nodiratime,discard 0 2' | sudo tee -a /etc/fstab

# Mount
sudo mount -a
```

Controleer:

```bash
df -h /opt/ipfs-data
```

### 1.4 IPFS (Kubo) installeren

```bash
# Maak een ipfs systeemgebruiker
sudo useradd -r -m -d /opt/ipfs-data -s /bin/bash ipfs

# Download de laatste Kubo voor ARM64
KUBO_VERSION="v0.35.0"
wget "https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-arm64.tar.gz"
tar -xzf "kubo_${KUBO_VERSION}_linux-arm64.tar.gz"
cd kubo
sudo bash install.sh
cd .. && rm -rf kubo kubo_*.tar.gz

# Initialiseer IPFS
export IPFS_PATH=/opt/ipfs-data/ipfs
sudo -u ipfs ipfs init --profile=lowpower

# Configureer voor SSD-gebruik
sudo -u ipfs ipfs config Datastore.StorageMax "200GB"
sudo -u ipfs ipfs config Datastore.StorageGCWatermark 85
sudo -u ipfs ipfs config Datastore.GCPeriod "1h"
sudo -u ipfs ipfs config Routing.Type "dhtclient"
sudo -u ipfs ipfs config Reprovider.Interval "12h"
sudo -u ipfs ipfs config Swarm.ConnMgr.LowWater 400
sudo -u ipfs ipfs config Swarm.ConnMgr.HighWater 800

# API en Gateway op localhost zetten (veiliger, cluster praat lokaal met API)
sudo -u ipfs ipfs config Addresses.API "/ip4/127.0.0.1/tcp/5001"
sudo -u ipfs ipfs config Addresses.Gateway "/ip4/127.0.0.1/tcp/8080"

# CORS voor lokale toegang
sudo -u ipfs ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["http://localhost:*", "http://127.0.0.1:*"]'
sudo -u ipfs ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["PUT", "GET", "POST"]'
```

### 1.5 IPFS systemd service aanmaken

```bash
sudo tee /etc/systemd/system/ipfs.service << 'EOF'
[Unit]
Description=IPFS daemon
After=network.target

[Service]
Type=notify
User=ipfs
Group=ipfs
Environment=IPFS_PATH=/opt/ipfs-data/ipfs
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=always
RestartSec=5
LimitNOFILE=65536
MemoryHigh=1G
MemoryMax=1.5G

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl start ipfs

# Controleer
sudo systemctl status ipfs
ipfs id
```

### 1.6 ArtBox management tools installeren

```bash
# Clone de ArtBox repo
cd /opt
sudo git clone https://github.com/AfroV/ArtBox.git artbox
cd artbox/nft_setup

# Maak Python venv en installeer dependencies
sudo python3 -m venv /opt/ipfs-data/venv
sudo /opt/ipfs-data/venv/bin/pip install requests web3 ipfshttpclient pillow

# Installeer de ipfs-tools CLI wrapper
sudo tee /usr/local/bin/ipfs-tools << 'SCRIPT'
#!/bin/bash
export IPFS_PATH=/opt/ipfs-data/ipfs
TOOLS_DIR=/opt/artbox/nft_setup
VENV=/opt/ipfs-data/venv/bin/python

case "${1:-}" in
  status)
    echo "=== IPFS Service ==="
    systemctl is-active ipfs
    echo ""
    echo "=== IPFS Peer ID ==="
    ipfs id | jq -r '.ID'
    echo ""
    echo "=== Connected Peers ==="
    ipfs swarm peers 2>/dev/null | wc -l
    echo "peers connected"
    echo ""
    echo "=== Disk Usage ==="
    du -sh /opt/ipfs-data/ipfs 2>/dev/null
    df -h /opt/ipfs-data
    ;;
  ssd-health)
    sudo smartctl -a /dev/sda 2>/dev/null | grep -E 'Model|Capacity|Power_On|Wear_Level|Reallocated|Temperature' || echo "SMART not available"
    ;;
  download)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Usage: ipfs-tools download <contract_address> <token_id>"
      exit 1
    fi
    sudo $VENV "$TOOLS_DIR/nft_downloader.py" "$2" "$3"
    ;;
  csv)
    if [ -z "$2" ]; then
      echo "Usage: ipfs-tools csv <file.csv>"
      exit 1
    fi
    sudo $VENV "$TOOLS_DIR/process_nft_csv.py" "$2"
    ;;
  monitor)
    INTERVAL="${2:-60}"
    echo "Monitoring every ${INTERVAL}s. Press Ctrl+C to stop."
    while true; do
      clear
      echo "=== IPFS Monitor — $(date) ==="
      echo "Service: $(systemctl is-active ipfs)"
      echo "Peers: $(ipfs swarm peers 2>/dev/null | wc -l)"
      echo "Storage: $(du -sh /opt/ipfs-data/ipfs 2>/dev/null | cut -f1)"
      sleep "$INTERVAL"
    done
    ;;
  backup)
    sudo bash "$TOOLS_DIR/ipfs_backup_restore.sh" backup
    ;;
  *)
    echo "ArtBox IPFS Tools"
    echo "  status              Show IPFS node status"
    echo "  ssd-health          Show SSD health info"
    echo "  download <addr> <id> Download single NFT"
    echo "  csv <file.csv>      Batch process NFTs"
    echo "  monitor [interval]  Continuous monitoring"
    echo "  backup              Create full backup"
    ;;
esac
SCRIPT

sudo chmod +x /usr/local/bin/ipfs-tools

# Test
ipfs-tools status
```

---

## Deel 2 — IPFS Cluster volunteer toevoegen

### 2.1 ipfs-cluster-service installeren

Download de binary voor ARM64. **Gebruik dezelfde versie als de coordinator.**
Controleer de coordinator-versie met: `docker exec cluster ipfs-cluster-service --version`

```bash
# Vervang <VERSION> met de coordinator-versie, bv. 1.0.8
CLUSTER_VERSION="1.0.8"

cd /tmp
wget "https://dist.ipfs.tech/ipfs-cluster-service/v${CLUSTER_VERSION}/ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
tar -xzf "ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-follow /usr/local/bin/
rm -rf ipfs-cluster-service ipfs-cluster-service_*.tar.gz

# Controleer
ipfs-cluster-service --version
ipfs-cluster-ctl --version
```

### 2.2 Cluster data directory aanmaken

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster
```

### 2.3 Cluster configuratiebestand aanmaken

**Let op:** vervang `<CLUSTER_SECRET>`, `<COORDINATOR_PEER_ID>` en `<PEERNAME>` met de
echte waarden (de secret krijg je van de coordinator).

```bash
# Maak de config directory
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster

# Initieer de cluster config (doet niets met IPFS_PATH, gebruikt eigen data dir)
sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt
'
```

Nu pas je `service.json` aan met de juiste waardes:

```bash
sudo -u ipfs bash -c '
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

# --- STEL HIER JE WAARDES IN ---
CLUSTER_SECRET="<HIER_JE_SECRET_INVULLEN>"
COORDINATOR_PEER_ID="<coordinator-peer-id>"
CLUSTER_PEERNAME="artbox-pi-jan"    # kies een unieke naam
COORDINATOR_IP="<coordinator-ip>"

# 1. Secret instellen
ipfs-cluster-service config set secret "${CLUSTER_SECRET}"

# 2. Peernaam
ipfs-cluster-service config set peername "${CLUSTER_PEERNAME}"

# 3. REST API op alle interfaces + plain HTTP (voor dashboard)
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# 4. Verbind met lokale IPFS API
sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5001|" service.json

# 5. Bootstrap naar coordinator
ipfs-cluster-service config set cluster.bootstrap "[
  \"/ip4/${COORDINATOR_IP}/tcp/9096/p2p/${COORDINATOR_PEER_ID}\"
]"

# 6. Alleen coordinator mag pins wijzigen (read-only volunteer via follower_mode)
ipfs-cluster-service config set trusted_peers "[\"${COORDINATOR_PEER_ID}\"]"
ipfs-cluster-service config set follower_mode true
'
```

Controleer de configuratie:

```bash
sudo cat /opt/ipfs-data/cluster/service.json | python3 -m json.tool | head -30
```

### 2.4 IPFS Cluster systemd service aanmaken

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
ExecStartPre=/bin/sh -c 'for i in $(seq 1 30); do curl -s http://127.0.0.1:5001/api/v0/version >/dev/null 2>&1 && exit 0; echo "Waiting for IPFS API..."; sleep 2; done; echo "IPFS API not ready after 60s"; exit 1'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-cluster
```

### 2.5 Firewall openzetten

```bash
# IPFS swarm (P2P verkeer)
sudo ufw allow 4001/tcp
sudo ufw allow 4001/udp

# IPFS Cluster gossip (verbinding met coordinator en andere peers)
sudo ufw allow 9096/tcp

# Optioneel: beperk 9096 tot alleen de coordinator voor extra veiligheid
# sudo ufw allow from <coordinator-ip> to any port 9096 proto tcp

# Activeer firewall (alleen als SSH niet geblokkeerd wordt)
sudo ufw allow 22/tcp
sudo ufw --force enable
sudo ufw status verbose
```

**Router:** Zorg dat poort **4001** (TCP+UDP) en **9096** (TCP) worden doorgestuurd
(port forwarding) naar het lokale IP van de Raspberry Pi.

### 2.6 Starten en verifiëren

```bash
# Herstart IPFS eerst (zodat de cluster op een verse API kan verbinden)
sudo systemctl restart ipfs
sleep 5

# Start cluster
sudo systemctl start ipfs-cluster

# Bekijk logs
sudo journalctl -u ipfs-cluster -f
# (Ctrl+C om te stoppen met loggen)
```

Wacht tot je in de logs ziet dat de peer verbonden is. Controleer daarna:

```bash
# Check cluster peer ID
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id

# Check of je verbonden bent met de coordinator
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

Je zou nu **minimaal 2 peers** moeten zien: je eigen peer en de coordinator.

```bash
# Check IPFS peer connectiviteit
ipfs swarm peers | wc -l
```

### 2.7 Beide services samen controleren

```bash
# Status van beide
sudo systemctl status ipfs ipfs-cluster

# Automatisch starten bij boot?
sudo systemctl is-enabled ipfs ipfs-cluster
```

---

## Deel 3 — Wat gebeurt er nu?

Zodra de coordinator jouw peer ziet, worden de volgende stappen handmatig uitgevoerd:

1. **Coordinator verhoogt replicatie** met `scripts/rebalance.sh` → CIDs worden
   verdeeld over jouw node en de coordinator (min replicatie = 2)
2. **Je node begint automatisch met downloaden** van de toegewezen CIDs
3. **Voortgang is live te zien** op het dashboard: **[https://glimmy.xyz](https://glimmy.xyz)**

Je hoeft zelf niets te doen — het cluster regelt de distributie.

---

## Deel 4 — Dagelijks beheer

```bash
# Status van je node
ipfs-tools status

# Cluster status (welke CIDs host je?)
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 status

# Hoeveel schijfruimte gebruik je?
du -sh /opt/ipfs-data/ipfs
df -h /opt/ipfs-data

# SSD gezondheid
ipfs-tools ssd-health

# Backup maken
sudo ipfs-tools backup

# Logs bekijken
sudo journalctl -u ipfs -n 50 --no-pager
sudo journalctl -u ipfs-cluster -n 50 --no-pager
```

---

## Troubleshooting

### "ipfs-cluster-service: command not found"
Controleer of de binary op de juiste plek staat:
```bash
ls -la /usr/local/bin/ipfs-cluster-*
```
Zo niet, herhaal stap 2.1.

### Cluster start niet: "secret mismatch"
De `CLUSTER_SECRET` in je `service.json` moet **exact** hetzelfde zijn als die van
de coordinator. Vraag de coordinator om bevestiging en pas aan:
```bash
sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service config set secret "<CORRECTE_SECRET>"
'
sudo systemctl restart ipfs-cluster
```

### "Cannot connect to IPFS API"
IPFS draait niet of de API is niet bereikbaar op `127.0.0.1:5001`:
```bash
sudo systemctl status ipfs
curl http://127.0.0.1:5001/api/v0/version
```
Als IPFS niet draait: `sudo systemctl restart ipfs`

### Peer verschijnt niet op het dashboard
1. Check of poort 9096 open is vanuit het internet
2. Check of de coordinator bereikbaar is: `nc -zv <coordinator-ip> 9096`
3. Check logs: `sudo journalctl -u ipfs-cluster -n 100 --no-pager | grep -i error`

### Geen peers in IPFS swarm
Controleer of poort 4001 open is (zowel op de Pi als in je router):
```bash
sudo ufw status | grep 4001
ss -tuln | grep 4001
```

### Te weinig schijfruimte
Pas de storage limiet aan:
```bash
sudo -u ipfs ipfs config Datastore.StorageMax "100GB"
sudo systemctl restart ipfs ipfs-cluster
```

---

## Samenvatting

Na deze setup heb je:

| Component | Locatie | Status |
|-----------|---------|--------|
| IPFS (Kubo) | systemd `ipfs.service` | ✅ Draait |
| IPFS Cluster peer | systemd `ipfs-cluster.service` | ✅ Verbonden met coordinator |
| ArtBox tools | `/usr/local/bin/ipfs-tools` | ✅ Beschikbaar |
| Data | `/opt/ipfs-data/` op SSD | ✅ Geoptimaliseerd |
| Firewall | ufw, poorten 4001+9096 open | ✅ Actief |

Je Pi is nu een actieve volunteer in het CyberWatch cluster en host automatisch
een deel van de 111+ curated CIDs.