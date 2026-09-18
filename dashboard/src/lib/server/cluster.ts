const API = process.env.CLUSTER_API_URL || 'http://cluster:9094';
const TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;

let reqId = 0;

function nextId(): string {
  reqId += 1;
  return String(reqId);
}

class ClusterError extends Error {
  constructor(
    message: string,
    public status: number,
    public requestId: string
  ) {
    super(message);
    this.name = 'ClusterError';
  }
}

async function fetchWithTimeout(url: string, init?: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(url, { ...init, signal: controller.signal });
    return res;
  } finally {
    clearTimeout(timer);
  }
}

function sanitize(message: string): string {
  return message.length > 500 ? message.slice(0, 500) + '...' : message;
}

async function get(path: string) {
  const id = nextId();
  let res: Response;
  try {
    res = await fetchWithTimeout(`${API}${path}`);
  } catch (e) {
    console.error(`[${id}] GET ${path}: request failed`, e);
    throw new ClusterError('Cluster unavailable', 0, id);
  }

  if (!res.ok) {
    const err = await res.text().catch(() => '');
    console.error(`[${id}] GET ${path}: HTTP ${res.status} — ${sanitize(err)}`);
    throw new ClusterError('Cluster request failed', res.status, id);
  }

  const cl = res.headers.get('content-length');
  if (cl && Number(cl) > MAX_RESPONSE_BYTES) {
    console.error(`[${id}] GET ${path}: response too large (${cl} bytes)`);
    throw new ClusterError('Response too large', 0, id);
  }

  const text = await res.text();
  if (!text) return null;

  if (text.length > MAX_RESPONSE_BYTES) {
    console.error(`[${id}] GET ${path}: response exceeded limit (${text.length} bytes)`);
    throw new ClusterError('Response too large', 0, id);
  }

  return JSON.parse(text);
}

async function post(path: string) {
  const id = nextId();
  let res: Response;
  try {
    res = await fetchWithTimeout(`${API}${path}`, { method: 'POST' });
  } catch (e) {
    console.error(`[${id}] POST ${path}: request failed`, e);
    throw new ClusterError('Cluster unavailable', 0, id);
  }

  if (!res.ok) {
    const err = await res.text().catch(() => '');
    console.error(`[${id}] POST ${path}: HTTP ${res.status} — ${sanitize(err)}`);
    throw new ClusterError('Cluster request failed', res.status, id);
  }

  return res.json();
}

async function del(path: string) {
  const id = nextId();
  let res: Response;
  try {
    res = await fetchWithTimeout(`${API}${path}`, { method: 'DELETE' });
  } catch (e) {
    console.error(`[${id}] DELETE ${path}: request failed`, e);
    throw new ClusterError('Cluster unavailable', 0, id);
  }

  if (!res.ok) {
    const err = await res.text().catch(() => '');
    console.error(`[${id}] DELETE ${path}: HTTP ${res.status} — ${sanitize(err)}`);
    throw new ClusterError('Cluster request failed', res.status, id);
  }

  return res.json();
}

export type PeerInfo = {
  id: string;
  addresses: string[];
  cluster_peers: string[];
  version: string;
  ipfs: { id: string; addresses: string[]; error: string };
  peername: string;
};

export type PinInfo = {
  cid: string;
  name: string;
  allocations: string[];
  peer_map: Record<string, { peername: string; status: string; error: string }>;
  replication_factor_min: number;
  replication_factor_max: number;
};

export function getId(): Promise<PeerInfo> {
  return get('/id');
}

export function getPeers(): Promise<PeerInfo> {
  return get('/peers');
}

export function getPins(): Promise<PinInfo[]> {
  const id = nextId();
  return fetchWithTimeout(`${API}/pins`)
    .then(async (res) => {
      if (!res.ok) {
        const err = await res.text().catch(() => '');
        console.error(`[${id}] GET /pins: HTTP ${res.status} — ${sanitize(err)}`);
        throw new ClusterError('Cluster request failed', res.status, id);
      }

      const cl = res.headers.get('content-length');
      if (cl && Number(cl) > MAX_RESPONSE_BYTES) {
        console.error(`[${id}] GET /pins: response too large (${cl} bytes)`);
        throw new ClusterError('Response too large', 0, id);
      }

      const text = await res.text();
      if (!text || !text.trim()) return [];

      if (text.length > MAX_RESPONSE_BYTES) {
        console.error(`[${id}] GET /pins: response exceeded limit (${text.length} bytes)`);
        throw new ClusterError('Response too large', 0, id);
      }

      const trimmed = text.trim();
      const lines = trimmed.split('\n');
      if (lines.length > 1 && lines[0].startsWith('{') && lines[1].startsWith('{')) {
        return lines.map((l) => JSON.parse(l)).filter((p) => p && p.cid);
      }
      if (trimmed[0] === '[') {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) return parsed;
        if (parsed.cid) return [parsed];
        return [];
      }
      if (trimmed[0] === '{') {
        const parsed = JSON.parse(trimmed);
        if (parsed.cid) return [parsed];
        return [];
      }
      return [];
    })
    .catch((e) => {
      if (e instanceof ClusterError) throw e;
      console.error(`[${id}] GET /pins: request failed`, e);
      throw new ClusterError('Cluster unavailable', 0, id);
    });
}

export function addPin(cid: string, replMin?: number, replMax?: number, name?: string): Promise<PinInfo> {
  const params = new URLSearchParams();
  if (replMin !== undefined) params.set('replication-min', String(replMin));
  if (replMax !== undefined) params.set('replication-max', String(replMax));
  if (name) params.set('name', name);
  const qs = params.toString();
  return post(`/pins/${cid}${qs ? '?' + qs : ''}`);
}

export function removePin(cid: string): Promise<PinInfo> {
  return del(`/pins/${cid}`);
}