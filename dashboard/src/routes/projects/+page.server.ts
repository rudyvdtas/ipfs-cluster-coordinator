import { getPins } from '$lib/server/cluster';
import { projects } from '$lib/server/projects';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
  try {
    const pins = await getPins();

    const safePins = pins.map((pin) => ({
      cid: pin.cid,
      name: pin.name,
      replication_factor_min: pin.replication_factor_min,
      replication_factor_max: pin.replication_factor_max,
      peer_allocations: Object.values(pin.peer_map ?? {}).map((info) => ({
        peername: info.peername,
        status: info.status
      }))
    }));

    return { projects, pins: safePins };
  } catch (e) {
    console.error('Projects load failed', e);
    return { error: 'Cluster data temporarily unavailable', projects: [], pins: [] };
  }
};
