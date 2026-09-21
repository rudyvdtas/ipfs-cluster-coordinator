# Volunteer — Cluster + Artbox

Add an IPFS Cluster volunteer to an **existing ArtBox** with Kubo.
The ArtBox owner needs a guarantee that their personal pins stay untouched.

The solution is a **second, separate Kubo instance** for the cluster.
Cluster CIDs and ArtBox CIDs never touch each other.

## Architecture

```
ArtBox Raspberry Pi
│
├── ipfs.service (ArtBox-Kubo)
│   └── owner's private CIDs (port 5001, IPFS_PATH=/opt/ipfs-data/ipfs)
│
├── ipfs-cluster-ipfs.service (Cluster-Kubo)
│   └── cluster CIDs only (port 5002, IPFS_PATH=/opt/ipfs-data/cluster-ipfs)
│
└── ipfs-cluster.service
    └── uses Cluster-Kubo API (5002), gossip on 9096
```

The cluster **never** talks to the ArtBox-Kubo. It uses its own Kubo
on port 5002 with its own peer ID and own repository.

### Why not reuse the ArtBox-Kubo?

Kubo cannot tell the difference between an ArtBox pin and a Cluster pin.
If the cluster rebalances and unpins a CID, it could remove an ArtBox pin.
`follower_mode=true` does not prevent this — it only prevents the volunteer
from *initiating* pinset changes itself.

A separate Cluster-Kubo is the only guarantee that ArtBox CIDs never disappear.

## Resource usage

| Service | RAM (idle) | RAM (active) |
|---------|-----------|-------------|
| ArtBox-Kubo | ~200 MB | ~400 MB |
| Cluster-Kubo | ~200 MB | ~400 MB |
| IPFS Cluster | ~50 MB | ~100 MB |
| **Total** | **~450 MB** | **~900 MB** |

- Raspberry Pi 4 (4GB+) or better
- At least 50 GB free disk space for cluster CIDs
- Ports `4002/tcp+udp` (Cluster-Kubo swarm) and `9096/tcp` (cluster gossip) open
- `ipfs-cluster-service` and `ipfs-cluster-ctl` binaries

## Step by step

### 1. Check the existing ArtBox-Kubo

```bash
sudo systemctl status ipfs
sudo -u ipfs ipfs config Path
```

Confirm it is running and note the `IPFS_PATH` (typically `/opt/ipfs-data/ipfs`).

### 2. Install a second Kubo (Cluster-Kubo)

Use the same version as the ArtBox-Kubo:

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

### 3. Initialize the Cluster-Kubo (separate repo)

```bash
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster-ipfs
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs init --profile=lowpower
'
```

This gets its own peer ID — normal and expected.

### 4. Configure the Cluster-Kubo

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

Note: separate API port (5002), separate swarm port (4002).

### 5. Create the Cluster-Kubo systemd service

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

### 6. Install IPFS Cluster binaries

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

### 7. Initialize and configure the cluster

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

  # Point to Cluster-Kubo (port 5002), NOT the ArtBox-Kubo (5001)
  sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5002|" service.json
  sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

  ipfs-cluster-service config set cluster.bootstrap "[\"/ip4/$COORDINATOR_IP/tcp/9096/p2p/$COORDINATOR_PEER_ID\"]"
'
```

### 8. Create the cluster systemd service

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

### 9. Open the firewall and start

```bash
sudo ufw allow 4002/tcp
sudo ufw allow 4002/udp
sudo ufw allow 9096/tcp
sudo ufw status verbose

sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

### 10. Verify the setup

```bash
# Cluster peer ID
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id

# Connected peers
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls

# All three services running
sudo systemctl status ipfs ipfs-cluster-ipfs ipfs-cluster
```

### 11. Confirm isolation

```bash
# ArtBox pins — these should never change due to cluster activity
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls

# Cluster-Kubo identity (different peer ID from ArtBox)
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id
```

---

## Validation checklist

| Check | Command |
|-------|---------|
| ArtBox-Kubo peer ID | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs id` |
| Cluster-Kubo peer ID | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id` |
| Cluster connected | `ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls` |
| ArtBox pins unchanged | `sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls` |

See the full ArtBox guide at `how-to-cluster-artbox.md` for more details
and troubleshooting.