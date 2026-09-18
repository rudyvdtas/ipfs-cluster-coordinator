# IPFS Cluster Monitor Dashboard

SvelteKit dashboard for managing an IPFS Cluster. Communicates with the
cluster REST API over the shared `cluster-internal` Docker network.

## Prerequisites

- Docker
- The `cluster-internal` network must exist:
  ```
  docker network create cluster-internal
  ```
- The IPFS Cluster Coordinator (separate repo) must be running on the same host

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_API_URL` | `http://cluster:9094` | URL of the cluster REST API |
| `DOMAIN` | `dashboard.localhost` | Domain for Traefik routing |

## Deploy

```
docker compose up -d --build
```

The dashboard is accessible via:
- Traefik at the configured `DOMAIN`
- Internally on port 3000 within the Docker network

## Architecture

```
Browser → Traefik → dashboard:3000 → cluster:9094 (REST API)
```

All communication with the cluster REST API happens server-side
(SvelteKit `+page.server.ts` / `+server.ts`). The browser never
talks directly to the cluster.

## API endpoints

The dashboard exposes these internal endpoints (used by the UI):

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Overview: peers, pin counts, latest pins |
| `GET` | `/pins` | Pin management page |
| `POST` | `/api/pins/add` | Add a CID to the pinset |
| `POST` | `/api/pins/remove` | Remove a CID from the pinset |

These endpoints call the cluster REST API (`http://cluster:9094`) server-side.

## Development

```
npm install
npm run dev
```

Set `CLUSTER_API_URL=http://localhost:9094` in `.env` if the cluster
REST API is port-forwarded for local development.