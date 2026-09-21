# Adding an IPFS Cluster volunteer to an existing ArtBox

This guide assumes an **existing, working ArtBox** with Kubo/IPFS.
You will add IPFS Cluster as a separate volunteer service alongside it.

**Safe architecture:** Cluster gets its **own, separate Kubo instance**. This keeps the
ArtBox owner's personal pinset safe from Cluster rebalancing or pinset changes.

---

## Architecture

```
ArtBox Raspberry Pi
│
├── ipfs.service
│   └── ArtBox-Kubo (IPFS_PATH=/opt/ipfs-data/ipfs)
│       ├── owner's private CIDs
│       ├── API: 5001
│       └── gateway: 8080
│
├── ipfs-cluster-ipfs.service
│   └── Cluster-Kubo (IPFS_PATH=/opt/ipfs-data/cluster-ipfs)
│       ├── Cluster-managed CIDs only
│       ├── API: 5002
│       └── gateway: 8081 (if needed)
│
└── ipfs-cluster.service
    └── IPFS Cluster volunteer
        ├── uses the Cluster-Kubo API (5002)
        ├── Cluster API: 9094
        └── Cluster peer communication: 9096
```

IPFS Cluster does **not** talk to the ArtBox-Kubo. It uses its own Cluster-Kubo:

```
IPFS Cluster → http://127.0.0.1:5002 → Cluster-Kubo (separate repository)
```

### Why not reuse the ArtBox-Kubo?

```
ArtBox/Kubo
└── owner's local pins

IPFS Cluster ──> same Kubo API ──> same pinset
```

Kubo cannot tell the difference between a pin placed by the ArtBox owner and a pin placed
by Cluster. When Cluster removes a CID from the shared pinset (e.g. during rebalancing),
it can unpin a local ArtBox pin. `follower_mode=true` does not prevent this — it only
prevents the volunteer from *initiating* pinset changes itself.

A separate Cluster-Kubo is the only guarantee that ArtBox CIDs will never disappear due
to Cluster action.

**What stays the same:**
- ArtBox `ipfs.service` remains unchanged
- ArtBox tools (`ipfs-tools`) keep working
- ArtBox pinset is never touched by Cluster

**What is added:**
- Separate Kubo instance for Cluster at `/opt/ipfs-data/cluster-ipfs`
- `ipfs-cluster-ipfs.service` (systemd)
- `ipfs-cluster-service` + `ipfs-cluster-ctl` binaries
- `ipfs-cluster.service` (systemd)
- Cluster configuration at `/opt/ipfs-data/cluster`

**Note:** running two Kubo daemons uses additional memory (~200-400 MB each), CPU, and
disk space. On a Raspberry Pi 4 (4GB+) this is perfectly manageable, but be aware of it.

---

## Step-by-step guide

> **Critical:** Do not point the Cluster service at the ArtBox-Kubo repository
> (`/opt/ipfs-data/ipfs`). Doing so would let Cluster unpin your personal ArtBox CIDs.
> The Cluster-Kubo must use its **own repository** (`/opt/ipfs-data/cluster-ipfs`) on its
> **own API port** (5002). Throughout this guide, every `IPFS_PATH` and port reference
> has been chosen to enforce this separation. Double-check that you never substitute
> the ArtBox paths.

### 1. Check the existing ArtBox-Kubo

```bash
sudo systemctl status ipfs
```

Check the IPFS_PATH used by ArtBox (typically `/opt/ipfs-data/ipfs`):

```bash
sudo -u ipfs ipfs config Path
```

### 2. Install the Cluster-Kubo

Install a second Kubo for Cluster use. **Use the same version as the ArtBox-Kubo** to
keep the network protocol compatible.

```bash
# Detect the ArtBox-Kubo version
ARTBOX_KUBO_VERSION=$(/usr/local/bin/ipfs version | cut -d' ' -f3)
echo "$ARTBOX_KUBO_VERSION"

# Or set it manually
ARTBOX_KUBO_VERSION="v0.35.0"

cd /tmp
wget "https://dist.ipfs.tech/kubo/${ARTBOX_KUBO_VERSION}/kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
tar -xzf "kubo_${ARTBOX_KUBO_VERSION}_linux-arm64.tar.gz"
cd kubo
sudo bash install.sh
cd .. && rm -rf kubo kubo_*.tar.gz
```

### 3. Initialize the Cluster-Kubo in a separate directory

```bash
# Separate repository — not in /opt/ipfs-data/ipfs
sudo -u ipfs mkdir -p /opt/ipfs-data/cluster-ipfs

sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs
  ipfs init --profile=lowpower
'
```

The Cluster-Kubo will get its **own peer ID**. This is normal — it acts as an independent
IPFS node, used exclusively for Cluster traffic.

### 4. Configure the Cluster-Kubo

```bash
sudo -u ipfs bash -c '
  export IPFS_PATH=/opt/ipfs-data/cluster-ipfs

  # Storage: Cluster CIDs take up space alongside ArtBox CIDs
  ipfs config Datastore.StorageMax "100GB"
  ipfs config Datastore.StorageGCWatermark 85
  ipfs config Datastore.GCPeriod "1h"
  ipfs config Routing.Type "dhtclient"
  ipfs config Reprovider.Interval "0"  # Cluster does not republish

  # API on a different port than the ArtBox-Kubo
  ipfs config Addresses.API "/ip4/127.0.0.1/tcp/5002"
  ipfs config Addresses.Gateway "/ip4/127.0.0.1/tcp/8081"

  # Swarm on a different port than the ArtBox-Kubo (4001)
  ipfs config Addresses.Swarm "[\"/ip4/0.0.0.0/tcp/4002\", \"/ip6/::/tcp/4002\"]"
'
```

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
sudo systemctl enable ipfs-cluster-ipfs
sudo systemctl start ipfs-cluster-ipfs

# Verify
sudo systemctl status ipfs-cluster-ipfs
```

Test that the API is reachable:

```bash
curl http://127.0.0.1:5002/api/v0/version
```

### 6. Install the IPFS Cluster binaries

**Use the same version as the coordinator.**
Check the coordinator version with: `docker exec cluster ipfs-cluster-service --version`

```bash
CLUSTER_VERSION="1.0.8"

cd /tmp
wget "https://dist.ipfs.tech/ipfs-cluster-service/v${CLUSTER_VERSION}/ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
tar -xzf "ipfs-cluster-service_v${CLUSTER_VERSION}_linux-arm64.tar.gz"
sudo cp ipfs-cluster-service/ipfs-cluster-service /usr/local/bin/
sudo cp ipfs-cluster-service/ipfs-cluster-ctl /usr/local/bin/
rm -rf ipfs-cluster-service ipfs-cluster-service_*.tar.gz

# Verify
ipfs-cluster-service --version
ipfs-cluster-ctl --version
```

### 7. Initialize the Cluster configuration

```bash
# Separate directory for Cluster config
sudo mkdir -p /opt/ipfs-data/cluster
sudo chown -R ipfs:ipfs /opt/ipfs-data/cluster

sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service init --consensus crdt
'
```

### 8. Configure Cluster

Replace the placeholders with actual values (secret and peer ID come from the coordinator):

```bash
sudo -u ipfs bash -c '
export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster

# --- SET YOUR VALUES HERE ---
CLUSTER_SECRET="<YOUR_CLUSTER_SECRET>"
COORDINATOR_PEER_ID="<coordinator-peer-id>"
CLUSTER_PEERNAME="artbox-pi-jan"
COORDINATOR_IP="<coordinator-ip>"

# 1. Cluster secret
ipfs-cluster-service config set secret "${CLUSTER_SECRET}"

# 2. Peer name
ipfs-cluster-service config set peername "${CLUSTER_PEERNAME}"

# 3. REST API over HTTP (for local status checks)
sed -i "s|/ip4/127.0.0.1/tcp/9094|/ip4/127.0.0.1/tcp/9094/http|" service.json

# 4. Connect to the Cluster-Kubo (not the ArtBox-Kubo)
sed -i "s|/ip4/127.0.0.1/tcp/5001|/ip4/127.0.0.1/tcp/5002|" service.json

# 5. Bootstrap to the coordinator
ipfs-cluster-service config set cluster.bootstrap "[
  \"/ip4/${COORDINATOR_IP}/tcp/9096/p2p/${COORDINATOR_PEER_ID}\"
]"

# 6. Follower mode
ipfs-cluster-service config set follower_mode true

# NOTE: follower_mode only prevents THIS node from initiating pinset
# changes. It does NOT prevent the coordinator from unpinning CIDs
# assigned to this volunteer, which is why we use a separate Kubo.
'
```

Verify the resulting config:

```bash
sudo cat /opt/ipfs-data/cluster/service.json | python3 -m json.tool | head -40
```

### 9. Create the IPFS Cluster systemd service

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

# Wait for the Cluster-Kubo API to be ready (port 5002)
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

### 10. Open the firewall

The ArtBox firewall probably already has port 4001 open. The Cluster-Kubo uses 4002 —
this also needs to be open for IPFS network traffic. Cluster gossip (9096) must be open
to the coordinator.

```bash
# Cluster-Kubo swarm
sudo ufw allow 4002/tcp
sudo ufw allow 4002/udp

# IPFS Cluster gossip
sudo ufw allow 9096/tcp

# Optional: restrict 9096 to the coordinator only
# sudo ufw allow from <coordinator-ip> to any port 9096 proto tcp

sudo ufw status verbose
```

### 11. Start and test

```bash
# Start cluster
sudo systemctl start ipfs-cluster

# Follow the logs
sudo journalctl -u ipfs-cluster -f
```

Wait until the peer connects, then test:

```bash
# Check cluster peer ID
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 id

# Check if you are connected to the coordinator
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

You should see **at least 2 peers**: your own peer and the coordinator.

### 12. Verify all services

```bash
sudo systemctl status ipfs ipfs-cluster-ipfs ipfs-cluster
sudo systemctl is-enabled ipfs ipfs-cluster-ipfs ipfs-cluster
```

### 13. Validation checklist

Run these commands to confirm the separation is working correctly:

```bash
# 1. Confirm Cluster-Kubo has its own identity (different peer ID from ArtBox)
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/cluster-ipfs ipfs id

# 2. List the ArtBox-Kubo pins — these should never change due to Cluster
sudo -u ipfs env IPFS_PATH=/opt/ipfs-data/ipfs ipfs pin ls

# 3. Confirm volunteer is connected to the coordinator in the cluster
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 peers ls
```

After Cluster has been running for a while, re-run command #2. The ArtBox pin list should
be identical — this confirms the two repositories are truly isolated.

---

| Service | Role | IPFS_PATH | API |
|---|---|---|---|
| `ipfs.service` | ArtBox-Kubo (private CIDs) | `/opt/ipfs-data/ipfs` | 5001 |
| `ipfs-cluster-ipfs.service` | Cluster-Kubo (Cluster CIDs) | `/opt/ipfs-data/cluster-ipfs` | 5002 |
| `ipfs-cluster.service` | Cluster volunteer | `/opt/ipfs-data/cluster` | 9094 |

The ArtBox owner manages their own CIDs through port 5001. Cluster manages shared CIDs
through the Cluster-Kubo on port 5002. They cannot interfere with each other.

---

## What happens next

Once the coordinator sees your peer, the cluster can be expanded:

1. **Coordinator increases replication** → CIDs are distributed to your node
2. **Your Cluster-Kubo starts downloading** the assigned CIDs
3. **Progress is visible** on the dashboard

The ArtBox stays untouched — none of the owner's pins are affected.

---

## Resource usage

Running two Kubo daemons side by side uses additional memory. On a Raspberry Pi 4:

| Service | RAM (idle) | RAM (active) |
|---|---|---|
| ArtBox-Kubo | ~200 MB | ~400 MB |
| Cluster-Kubo | ~200 MB | ~400 MB |
| IPFS Cluster | ~50 MB | ~100 MB |
| **Total** | **~450 MB** | **~900 MB** |

A 4GB Raspberry Pi has enough headroom. With 8GB there is no concern at all.

Disk space: Cluster CIDs are downloaded to `/opt/ipfs-data/cluster-ipfs`. Keep this in
mind when sizing the partition.

---

## Daily operations

```bash
# ArtBox status
ipfs-tools status

# Cluster status — which CIDs are you hosting?
ipfs-cluster-ctl --host /ip4/127.0.0.1/tcp/9094 status

# Logs
sudo journalctl -u ipfs -n 50 --no-pager
sudo journalctl -u ipfs-cluster-ipfs -n 50 --no-pager
sudo journalctl -u ipfs-cluster -n 50 --no-pager
```

---

## Troubleshooting

### Cluster won't start: "secret mismatch"
```bash
sudo -u ipfs bash -c '
  export IPFS_CLUSTER_PATH=/opt/ipfs-data/cluster
  ipfs-cluster-service config set secret "<CORRECT_SECRET>"
'
sudo systemctl restart ipfs-cluster
```

### Cluster-Kubo API not reachable
```bash
sudo systemctl status ipfs-cluster-ipfs
curl http://127.0.0.1:5002/api/v0/version
```

If the Cluster-Kubo is not running: `sudo systemctl restart ipfs-cluster-ipfs`

### Peer not showing up on the dashboard
```bash
sudo journalctl -u ipfs-cluster -n 100 --no-pager | grep -i error
nc -zv <coordinator-ip> 9096
```

### ArtBox-Kubo and Cluster-Kubo swarm ports
Check that both ports are open:

```bash
sudo ufw status | grep -E '4001|4002'
ss -tuln | grep -E '4001|4002'
```