<script lang="ts">
  let data = $props() as { data: any };

  let allProjects = $derived(data.data?.projects ?? []);
  let pins = $derived(data.data?.pins ?? []);
  let error = $derived(data.data?.error);
  let activeTab = $state(allProjects.length > 0 ? allProjects[0].id : null);
  let showCids = $state(false);

  let activeProject = $derived(allProjects.find((p: any) => p.id === activeTab));
  let projectCids = $derived(pins.length > 0 ? pins : []);
  let pinnedCount = $derived(
    projectCids.filter((p: any) => (p.peer_allocations ?? []).some((i: any) => i.status === 'pinned')).length
  );
  let peerCount = $derived(
    projectCids.reduce((max: number, pin: any) => Math.max(max, (pin.peer_allocations ?? []).length), 0)
  );
  let peerStats = $derived(
    projectCids.reduce((acc: Record<string, number>, pin: any) => {
      (pin.peer_allocations ?? []).forEach((info: any) => {
        acc[info.peername] = (acc[info.peername] || 0) + 1;
      });
      return acc;
    }, {} as Record<string, number>)
  );
</script>

<h1 style="margin-bottom: 0.25rem;">Projects</h1>
<p class="text-muted" style="margin-bottom: 1rem;">Curated CIDs grouped by project — each project's content is replicated across volunteer peers.</p>

{#if error}
  <div class="card" style="border-color: var(--red); color: var(--red);">{error}</div>
{:else}
  <div class="tabs">
    {#each allProjects as project}
      <button
        class="tab {activeTab === project.id ? 'active' : ''}"
        onclick={() => { activeTab = project.id; showCids = false; }}
      >
        {project.name}
      </button>
    {/each}
  </div>

  {#if activeProject}
    <div class="card card-accent" style="margin-bottom: 1rem;">
      <div class="flex-between" style="margin-bottom: 0.5rem;">
        <div>
          <strong style="font-size: 1rem;">{activeProject.name}</strong>
          <p class="text-muted text-sm" style="margin-top: 0.25rem;">{activeProject.description}</p>
        </div>
        <div class="flex gap-sm">
          <div class="badge badge-success">{pinnedCount} pinned</div>
          <div class="badge badge-info">{projectCids.length} CIDs</div>
          <div class="badge" style="background: #e8f8f5; color: var(--accent-dark);">{peerCount} peers</div>
        </div>
      </div>
      <button
        class="primary"
        style="font-size: 0.8rem; margin-top: 0.5rem;"
        onclick={() => showCids = !showCids}
      >
        {showCids ? 'Hide CID list' : 'Show CID list'}
      </button>
    </div>

  {#if showCids && projectCids.length > 0}
    <div class="card" style="margin-bottom: 1rem;">
        <h2>Curated CIDs ({projectCids.length})</h2>
        <div style="max-height: 350px; overflow-y: auto; margin-top: 0.5rem;">
          <table>
            <thead>
              <tr>
                <th>CID</th>
                <th>Status</th>
                <th>Peers</th>
              </tr>
            </thead>
            <tbody>
              {#each projectCids as pin}
                {@const peerEntries = pin.peer_allocations ?? []}
                <tr>
                  <td>
                    <a href="https://dweb.link/ipfs/{pin.cid}" target="_blank" rel="noopener" title="Open via IPFS gateway">
                      <code style="color:var(--accent);">{pin.cid.slice(0, 30)}...</code>
                    </a>
                  </td>
                  <td>
{#each peerEntries as info}
                                    <span class="badge {info.status === 'pinned' ? 'badge-success' : info.status === 'pinning' ? 'badge-warning' : info.status.includes('error') ? 'badge-error' : 'badge-info'}">
                                      {info.status}
                                    </span>
                                  {/each}
                  </td>
                  <td>
                    <div class="flex gap-sm" style="flex-wrap: wrap;">
{#each peerEntries as info}
                                  <span class="text-muted text-sm">{info.peername}</span>
                                {:else}
                        <span class="text-muted text-sm">—</span>
                      {/each}
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    <div class="card">
      <h2>Replication Overview</h2>
      <p class="text-muted text-sm" style="margin-bottom: 1rem;">
        Each CID is allocated to a subset of peers based on replication factor.
        The cluster automatically assigns content when volunteers join.
      </p>
      <table>
        <thead>
          <tr>
            <th>Peer</th>
            <th>CIDs hosted</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {#each Object.entries(peerStats) as [peerName, count]}
            <tr>
              <td><strong>{peerName}</strong></td>
              <td>{count} CIDs</td>
              <td><span class="badge badge-success">online</span></td>
            </tr>
          {:else}
            <tr>
              <td colspan="3" class="text-muted">No peers have allocated CIDs yet. Wait for volunteers to join.</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
{/if}