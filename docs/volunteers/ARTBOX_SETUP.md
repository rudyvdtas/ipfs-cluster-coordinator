# Volunteer Setup: ArtBox with Separate Cluster Kubo

This setup is for an ArtBox owner who wants to join the cluster **without risking their personal pins**.

The solution is a **second, separate Kubo instance** for the cluster. Cluster pins and ArtBox pins never mix.

## Architecture

```
ArtBox machine
│
├── ipfs.service (ArtBox-Kubo)
│   ├── owner's private pins
│   ├── IPFS_PATH=/opt/ipfs-data/ipfs
│   └── API on port 5001
│
├── ipfs-cluster-ipfs.service (Cluster-Kubo)
│   ├── cluster-managed pins only
│   ├── IPFS_PATH=/opt/ipfs-data/cluster-ipfs
│   └── API on port 5002
│
└── ipfs-cluster.service
    ├── uses Cluster-Kubo API (port 5002)
    ├── Cluster REST API on port 9094
    └── Cluster gossip on port 9096
```

### Why two Kubo instances?

Kubo cannot distinguish between a pin placed by the ArtBox owner and a pin placed by the cluster. If the cluster rebalances and unpins a CID, it could accidentally unpin an ArtBox pin. **A separate Cluster-Kubo guarantees complete isolation.**

## Requirements

- Raspberry Pi 4+ (4GB+ RAM) or similar machine
- At least 50 GB free disk space for cluster CIDs
- Ports `4002/tcp+udp` (Cluster-Kubo swarm) and `9096/tcp` (cluster gossip) open
- `ipfs-cluster-service` and `ipfs-cluster-ctl` binaries

## Installation

### 1. Verify existing ArtBox-Kubo

```bash
sudo systemctl status ipfs
sudo -u ipfs ipfs config Path
```

Note: it's typically `/opt/ipfs-data/ipfs`.

### 2. Install Cluster-Kubo (separate binary)

Use the **same Kubo version** as the ArtBox-Kubo:

```bash
ARTBOX_KUBO_VERSION=$(/usr/local/bin/ipfs version | cut -d' ' -f3)
echo "$ARTBOX_KUBO_VERSION"

cd /tmp
wget "https://dist.ipfs.tech/kubo/${ARTBOX_KUBO_VERSION}/kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
tar -xzf "kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
cd kubo
sudo bash install.sh
cd .. && rm -rf kubo kubo_*.tar.gz
```

### 3. Initialize Cluster-Kubo in a separate repo

```bash
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster-ipfs
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs init --profile=lowpower
'
```

It gets its **own peer ID** — normal and expected.

### 4. Configure Cluster-Kubo

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

**Key differences:**
- API port: `5002` (not 5001)
- Swarm port: `4002` (not 4001)
- Storage: `100GB` (for cluster CIDs only)

### 5. Create Cluster-Kubo systemd service

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
wget "https://dist.ipfs.tech/ipfs-cluster-service/v${CLUSTER_VERSION}/ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
tar -xzf "ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service *.tar.gz

ipfs-cluster-service --version
```

### 7. Initialize and configure cluster

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster

sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt

  CLUSTER_SECRET="<from coordinator>"
  COORDINATOR_PEER_ID="12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd"
  CLUSTER_PEERNAME="artbox-pi-jan"
  COORDINATOR_IP="<coordinator-ip>"

  sed -i "s|\"secret\".*|\"secret\": \"${CLUSTER_SECRET}\",|" service.json
  sed -i "s|\"peername\".*|\"peername\": \"${CLUSTER_PEERNAME}\",|" service.json
  sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json
  sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5002|" service.json
  sed -i "s|\"trusted_peers\".*|\"trusted_peers\": [\"${COORDINATOR_PEER_ID}\"],|" service.json
  sed -i "s|\"pin_only_on_trusted_peers\".*|\"pin_only_on_trusted_peers\": true,|" service.json
  sed -i "s|\"bootstrap\".*|\"bootstrap\": [\"/ip4/${COORDINATOR_IP}/tcp/9096/p2p/${COORDINATOR_PEER_ID}\"],|" service.json
'
```

### 8. Create cluster systemd service

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

### 9. Open firewall

```bash
# Cluster-Kubo swarm (separate from ArtBox-Kubo which uses 4001)
sudo ufw allow 4002/tcp
sudo ufw allow 4002/udp

# Cluster gossip to coordinator
sudo ufw allow 9096/tcp

sudo ufw status verbose
```

### 10. Start and verify

```bash
sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

After a few seconds, verify:

```bash
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

### 11. Confirm isolation

Verify the ArtBox pins are **never** modified by cluster activity:

```bash
# ArtBox pins (should never change)
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls

# Cluster-Kubo pins (different peer ID, separate repository)
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs pin ls
```

## Resource Usage

| Service | RAM (idle) | RAM (active) |
|---------|-----------|----------|
| ArtBox-Kubo | ~200 MB | ~400 MB |
| Cluster-Kubo | ~200 MB | ~400 MB |
| IPFS Cluster | ~50 MB | ~100 MB |
| **Total** | **~450 MB** | **~900 MB** |

A 4GB Raspberry Pi has plenty of headroom.

## Troubleshooting

**Cluster-Kubo API not reachable:**
```bash
sudo systemctl status ipfs-cluster-ipfs
curl http://127.0.0.1:5002/api/v0/version
```

**Cluster won't start:**
```bash
sudo systemctl restart ipfs-cluster-ipfs
sudo journalctl -u ipfs-cluster -n 100 --no-pager
```

**ArtBox pins disappeared:**

This is a configuration error. If you see this:
1. Verify both Kubo instances have different `IPFS_PATH`
2. Verify cluster points to port 5002, not 5001
3. Check service.json: `CLUSTER_IPFSHTTP_NODEMULTIADDRESS` should be `/ip4/127.0.0.1/tcp/5002`
