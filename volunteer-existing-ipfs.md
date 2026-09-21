# Volunteer — IPFS node + Cluster

Add IPFS Cluster alongside an **existing, running Kubo node**.
Your own IPFS node keeps working; the cluster uses your Kubo API
for managing assigned CIDs.

## Architecture

```
Your existing Kubo node
└── API on port 5001
    └── IPFS Cluster (systemd service)
        ├── uses your Kubo API
        ├── Cluster REST API: 9094
        └── Cluster gossip: 9096
```

**Why no separate Kubo?** Your existing node is sufficient. The cluster uses
`CLUSTER_CRDT_TRUSTEDPEERS` to restrict pinset writes to the coordinator;
volunteers receive allocations and host content but cannot modify the pinset.
The cluster can only add allocations to the existing pinset.

## Requirements

- A running Kubo node (systemd, Docker, or manual)
- Extra ~100 MB RAM for the cluster service
- At least 50 GB free disk space for cluster allocations
- Port `9096` (TCP) open to the coordinator
- `ipfs-cluster-service` and `ipfs-cluster-ctl` binaries

## Step by step

### 1. Check your existing Kubo

```bash
ipfs id
curl http://127.0.0.1:5001/api/v0/version
```

Note the port number (default 5001).

### 2. Download the cluster binaries

Use the same version as the coordinator (check with
`docker exec cluster ipfs-cluster-service --version`):

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

### 3. Initialize the cluster config

```bash
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R $USER:$USER /opt/ipfs-data/cluster
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
ipfs-cluster-service init --consensus crdt
```

### 4. Configure the cluster peer

```bash
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

CLUSTER_SECRET="<the secret the coordinator shared with you>"
COORDINATOR_PEER_ID="12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd"
CLUSTER_PEERNAME="my-machine-name"
COORDINATOR_IP="149.210.143.16"

# In v1.1.6, config set subcommand does not exist. Edit service.json directly.
sed -i "s|\"secret\":.*|\"secret\": \"$CLUSTER_SECRET\",|" service.json
sed -i "s|\"peername\":.*|\"peername\": \"$CLUSTER_PEERNAME\",|" service.json

# Trusted-peers enforcement: only the coordinator may modify the pinset
sed -i "s|\"trusted_peers\":.*|\"trusted_peers\": [\"$COORDINATOR_PEER_ID\"],|" service.json
sed -i "s|\"pin_only_on_trusted_peers\":.*|\"pin_only_on_trusted_peers\": true,|" service.json

# Point to your Kubo API (change port if yours is different)
sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5001|" service.json

# Enable plain HTTP for the REST API
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# Set bootstrap to the coordinator
sed -i "s|\"bootstrap\":.*|\"bootstrap\": [\"/ip4/$COORDINATOR_IP/tcp/9096/p2p/$COORDINATOR_PEER_ID\"],|" service.json
```

### 5. Create a systemd service

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

### 6. Open the firewall and start

```bash
sudo ufw allow 9096/tcp
sudo systemctl start ipfs-cluster
sudo journalctl -u ipfs-cluster -f
```

### 7. Verify the connection

```bash
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

You should see at least 2 peers: your own peer and the coordinator.

---

## FAQ

**Can the cluster remove my own pins?**
No. The cluster coordination via `CLUSTER_CRDT_TRUSTEDPEERS` ensures only the
coordinator can modify the pinset. The cluster can only add allocations.
Your own CIDs stay untouched.

**Which ports does the cluster use?**
- `9096`: cluster gossip (must be open to the coordinator)
- `9094`: cluster REST API (local only)