# Volunteer Setup: Systemd on Existing Kubo

This is an alternative to Docker for volunteers who already have a running Kubo instance on their machine.

## Requirements

- A running Kubo node (systemd, Docker, or manual)
- ~100 MB RAM for the cluster service
- At least 50 GB free disk space
- Port `9096` (TCP) open to the coordinator
- `ipfs-cluster-service` and `ipfs-cluster-ctl` binaries

## Installation

### 1. Download cluster binaries

Use the same version as the coordinator (check with `docker exec cluster ipfs-cluster-service --version`):

```bash
CLUSTER_VERSION="1.1.6"
ARCH="linux-arm64"   # or linux-amd64

wget "https://dist.ipfs.tech/ipfs-cluster-service/v$CLUSTER_VERSION/ipfs-cluster-service_v$CLUSTER_VERSION_$ARCH.tar.gz"
tar -xzf "ipfs-cluster-service_v$CLUSTER_VERSION_$ARCH.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service *.tar.gz

ipfs-cluster-service --version
```

### 2. Initialize cluster config

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R $USER:$USER /opt/ipfs-data/cluster
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
ipfs-cluster-service init --consensus crdt
```

### 3. Configure the cluster peer

```bash
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

CLUSTER_SECRET="<the secret from the coordinator>"
COORDINATOR_PEER_ID="12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd"
CLUSTER_PEERNAME="my-machine-name"
COORDINATOR_IP="<coordinator-ip>"

# Edit service.json with these settings
sed -i "s|\"secret\".*|\"secret\": \"$CLUSTER_SECRET\",|" service.json
sed -i "s|\"peername\".*|\"peername\": \"$CLUSTER_PEERNAME\",|" service.json
sed -i "s|\"trusted_peers\".*|\"trusted_peers\": [\"$COORDINATOR_PEER_ID\"],|" service.json
sed -i "s|\"pin_only_on_trusted_peers\".*|\"pin_only_on_trusted_peers\": true,|" service.json
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json
sed -i "s|\"bootstrap\".*|\"bootstrap\": [\"/ip4/$COORDINATOR_IP/tcp/9096/p2p/$COORDINATOR_PEER_ID\"],|" service.json
```

### 4. Create systemd service

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

### 5. Open firewall and start

```bash
sudo ufw allow 9096/tcp
sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

### 6. Verify connection

```bash
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

You should see at least 2 peers: yourself and the coordinator.

## FAQ

**Can the cluster remove my own pins?**

No. The `CLUSTER_CRDT_TRUSTEDPEERS` setting ensures only the coordinator can modify the pinset. The cluster can only add allocations.

**Which ports are needed?**

- `9096`: cluster gossip (must be open to coordinator)
- `9094`: cluster REST API (local only)
