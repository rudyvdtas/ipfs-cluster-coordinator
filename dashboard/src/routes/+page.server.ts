import { getId, getPeers, getPins } from '$lib/server/cluster';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
  try {
    const cluster = await getId();
    const peersData = await getPeers();
    const pins = await getPins();

    const peers = (Array.isArray(peersData) ? peersData : [peersData]).map((p: any) => ({
      peername: p.peername
    }));

    const volunteers = peers.length - 1;

    const statusCounts = { pinned: 0, pinning: 0, queued: 0, error: 0 };
    for (const pin of pins) {
      for (const info of Object.values(pin.peer_map ?? {})) {
        if (info.status === 'pinned') statusCounts.pinned++;
        else if (info.status === 'pinning') statusCounts.pinning++;
        else if (info.status === 'queued') statusCounts.queued++;
        else if (info.status.includes('error')) statusCounts.error++;
      }
    }

    const pinStatuses = pins.flatMap((pin) =>
      Object.values(pin.peer_map ?? {}).map((info) => ({
        cid: pin.cid,
        name: pin.name || pin.cid,
        peername: info.peername,
        status: info.status,
        replication_factor_min: pin.replication_factor_min,
        replication_factor_max: pin.replication_factor_max
      }))
    );

    return {
      cluster: { peername: cluster.peername },
      peers,
      volunteers,
      pinStatuses,
      pinCount: pins.length,
      statusCounts
    };
  } catch (e) {
    console.error('Dashboard load failed', e);
    return { error: 'Cluster data temporarily unavailable' };
  }
};