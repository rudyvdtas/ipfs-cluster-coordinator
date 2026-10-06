# IPv6 Bootstrap Setup for NAT-Behind Peers

## Problem

Peers behind NAT (home networks) cannot establish **bidirectional** connectivity with the coordinator via IPv4. This breaks IPFS Cluster CRDT synchronization because the coordinator cannot initiate inbound connections.

If you have a public IPv6 address, you can bypass this limitation entirely.

## Solution: IPv6 Bootstrap

The coordinator supports IPv6 gossip on port 9096. Peers with public IPv6 addresses can bootstrap directly over IPv6, establishing proper bidirectional connectivity.

## Setup Instructions

### 1. Verify your public IPv6 address

On your peer machine:

```bash
# Check available IPv6 addresses
ip -6 addr show

# Or (if behind a router):
curl -s https://api.ipify.org?format=json | jq
curl -s https://api6.ipify.org?format=json | jq  # IPv6
```

Example output:
```
/ip6/2a02:a459:8ac8:0:7d3f:3b5f:ac0d:694c/tcp/9096
```

### 2. Get the coordinator's IPv6 multiaddr

Contact the coordinator or check their deployment documentation for their public IPv6 address and Cluster Peer ID.

Format:
```
/ip6/<coordinator-ipv6>/tcp/9096/p2p/<coordinator-peer-id>
```

### 3. Update your peer's bootstrap configuration

In your peer's `.env` or `docker-compose.yml`, set:

```bash
BOOTSTRAP_PEERS="/ip6/<coordinator-ipv6>/tcp/9096/p2p/<coordinator-peer-id>"
```

**You can include both IPv4 and IPv6:**
```bash
BOOTSTRAP_PEERS="/ip4/<coordinator-ipv4>/tcp/9096/p2p/<coordinator-peer-id>,/ip6/<coordinator-ipv6>/tcp/9096/p2p/<coordinator-peer-id>"
```

### 4. Restart your peer

```bash
docker compose up -d
docker logs -f cluster
```

Look for messages like:
```
gossip: connected to peer [peer-id] via [ipv6-multiaddr]
```

### 5. Verify connectivity

```bash
docker exec cluster ipfs-cluster-ctl peers ls
```

Your peer should appear with status `HEALTHY` or `OK`.

## Troubleshooting

| Issue | Check |
|-------|-------|
| IPv6 connection times out | Firewall rules (ensure port 9096/TCP is open for IPv6) |
| Peer still not syncing | Check `CLUSTER_SECRET` matches coordinator |
| No IPv6 connectivity on host | ISP/network doesn't support IPv6 or requires configuration |

## Alternatives

If IPv6 is not available:
- **VPN/Tailscale**: Use a tunnel to bypass NAT
- **Port forwarding**: Configure your home router to forward port 9096 to your peer
- **Proxy peer**: Run a relay node with public IPv4 connectivity

## FAQ

**Q: Do I need IPv6 to join the cluster?**  
A: No—IPv4 works fine if you can achieve bidirectional connectivity (e.g., via VPN or port forwarding).

**Q: Can I use both IPv4 and IPv6?**  
A: Yes! IPFS Cluster will prefer working addresses.

**Q: What if my ISP doesn't support IPv6?**  
A: Use one of the alternatives listed above (VPN, port forwarding, or proxy).
