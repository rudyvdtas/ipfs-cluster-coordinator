<script lang="ts">
  let data = $props() as { data: any };
  let volunteers = $derived(data.data.volunteers ?? 0);
  let cidCount = $derived(data.data.cidCount ?? 0);
  let peerCount = $derived(data.data.peerCount ?? 1);
</script>

<h1 style="margin-bottom: 0.25rem;">Volunteer</h1>
<p class="text-muted" style="margin-bottom: 1.5rem;">
  {volunteers === 0 ? 'No volunteers yet — be the first!' : `${volunteers} active volunteer${volunteers > 1 ? 's' : ''}`}
  · {peerCount} peer{peerCount > 1 ? 's' : ''} · {cidCount} CIDs
</p>

<div class="card mb-md card-accent">
  <h2>Requirements</h2>
  <table>
    <thead>
      <tr><th>Item</th><th>Minimum</th></tr>
    </thead>
    <tbody>
      <tr><td>RAM</td><td>1.5–2 GB (idle ~500 MB–1 GB)</td></tr>
      <tr><td>Disk</td><td>Configurable — set <code>IPFS_STORAGE_MAX</code> in your <code>.env</code></td></tr>
      <tr><td>CPU</td><td>Any (ARM64 / AMD64 — RPi 3/4/5 works)</td></tr>
      <tr><td>Network</td><td>Port <code>4001</code> (TCP+UDP) open in your firewall</td></tr>
      <tr><td>Software</td><td>Docker (<code>curl -fsSL https://get.docker.com | sh</code>)</td></tr>
    </tbody>
  </table>
</div>

<div class="card mb-md card-accent">
  <h2>Step-by-step</h2>
  <ol style="padding-left: 1.25rem; line-height: 2.2;">
    <li>
      <strong>Install Docker</strong>
      <div class="text-muted text-sm">
        <strong>Linux / VPS / Raspberry Pi (production):</strong>
        <pre><code>curl -fsSL https://get.docker.com | sh</code></pre>
        <strong>macOS (testing only):</strong>
        Docker Desktop via <code>brew install --cask docker</code>,
        or <a href="https://docs.docker.com/desktop/setup/install/mac-install/" target="_blank" rel="noopener">download from docker.com</a>.
        Note: macOS peers are not reachable from the public internet.
      </div>
    </li>
    <li>
      <strong>Clone the coordinator repository</strong>
      <div class="text-muted text-sm">All configuration files and scripts are in this repo.</div>
      <pre><code>git clone https://github.com/rudyvdtas/ipfs-cluster-coordinator.git
cd ipfs-cluster-coordinator</code></pre>
    </li>
    <li>
      <strong>Configure your peer</strong>
      <div class="text-muted text-sm">Create your config file and fill in your peer name and storage limit.</div>
      <pre><code>cp .env.example .env
nano .env</code></pre>
      <div class="text-muted text-sm" style="margin-top: 0.25rem;">
        Set your <code>CLUSTER_PEERNAME</code> and <code>IPFS_STORAGE_MAX</code>.
        <strong>Contact us</strong> if you want to participate so we can share
        the needed SECRET to connect to the Cluster.
      </div>
    </li>
    <li>
      <strong>Open your firewall (Linux/VPS only)</strong>
      <div class="text-muted text-sm">Your node communicates with other peers on port 4001.</div>
      <pre><code>sudo ufw allow 4001/tcp
sudo ufw allow 4001/udp</code></pre>
      <div class="text-muted text-sm">
        If you use a cloud provider (Hetzner, TransIP, etc.), also open port 4001
        in their separate firewall panel.<br>
        <strong>macOS:</strong> Skip this step — firewall is not required for testing.
      </div>
    </li>
    <li>
      <strong>Create the Docker network &amp; start</strong>
      <div class="text-muted text-sm">This establishes the internal network the cluster uses.</div>
      <pre><code>docker network create cluster-internal
docker compose up -d</code></pre>
    </li>
    <li>
      <strong>Verify your connection</strong>
      <div class="text-muted text-sm">Wait 30 seconds, then run:</div>
      <pre><code>docker exec cluster ipfs-cluster-ctl id</code></pre>
      <div class="text-muted text-sm">
        If you see a valid peer ID (e.g. <code>12D3...</code>) and no errors,
        your node is connected and visible to the coordinator.
      </div>
    </li>
  </ol>
</div>

<div class="card">
  <h2>What happens after you join</h2>
  <p class="text-muted text-sm">
    Once your peer is visible in the cluster, the coordinator increases
    the replication factor so curated CIDs are distributed across your
    machine and the coordinator. From that point on, each CID is stored
    on at least 2 peers — the goal of the network is redundancy.
  </p>
  <p class="text-muted text-sm" style="margin-top: 0.75rem;">
    Your node automatically receives the assigned CIDs. You don't need to
    choose or manage anything. All content is verified and hosted by your
    IPFS node.
  </p>
  <p class="text-muted text-sm" style="margin-top: 0.75rem;">
    Check the status of all CIDs:
    <br>
    <code>docker exec cluster ipfs-cluster-ctl status</code>
  </p>
</div>