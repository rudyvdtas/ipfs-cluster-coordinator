#!/usr/bin/env python3
"""
IPFS Cluster — failed-CID tracker sidecar.

Polls the cluster REST API every POLL_INTERVAL seconds.
Tracks consecutive pin_error counts per CID.
After MAX_RETRIES errors: unpins the CID and adds it to the failed list.

Endpoints:
  GET  /failed-cids        → JSON array of failed CIDs
  GET  /status             → error_counts + failed_count (debug)
  GET  /summary            → cached aggregate pin-status counts (pinned/pinning/
                              queued/error/pin_count), computed once per poll —
                              never triggers a live cluster broadcast, safe to
                              call as often as needed regardless of pinset size.
  GET  /healthz            → {"status": "ok"}
  DELETE /failed-cids/{cid} → remove from failed list (manual retry)
"""

import json
import os
import sys
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

# ---------------------------------------------------------------------------
# Config (override via environment)
# ---------------------------------------------------------------------------
CLUSTER_API    = os.environ.get("CLUSTER_API", "http://cluster:9094")
POLL_INTERVAL  = int(os.environ.get("POLL_INTERVAL_SECONDS", "60"))
MAX_RETRIES    = int(os.environ.get("MAX_RETRIES", "5"))
SERVE_PORT     = int(os.environ.get("SERVE_PORT", "9095"))
STATE_FILE     = os.environ.get("STATE_FILE", "/data/failed-cids.json")

# Error statuses that count as a failed pin attempt
ERROR_STATUSES = {"pin_error", "error", "cluster_error", "remote_pin_error"}

# ---------------------------------------------------------------------------
# Shared state (guarded by state_lock)
# ---------------------------------------------------------------------------
state_lock   = threading.Lock()
error_counts = {}   # cid → consecutive error count
failed_cids  = set() # permanently failed CIDs
summary      = {}   # cached aggregate counts, computed once per poll (see poll_loop)

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

def load_state():
    if not os.path.exists(STATE_FILE):
        return
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        failed_cids.update(data.get("failed", []))
        error_counts.update(data.get("error_counts", {}))
        summary.update(data.get("summary", {}))
        print(f"[tracker] Loaded state: {len(failed_cids)} failed, "
              f"{len(error_counts)} in-progress", flush=True)
    except Exception as e:
        print(f"[tracker] Could not load state file: {e}", flush=True)


def save_state():
    """Write current state to disk (call with state_lock held)."""
    try:
        os.makedirs(os.path.dirname(os.path.abspath(STATE_FILE)), exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({
                "failed":       sorted(failed_cids),
                "error_counts": dict(error_counts),
                "summary":      dict(summary),
                "updated":      time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }, f, indent=2)
        os.replace(tmp, STATE_FILE)
    except Exception as e:
        print(f"[tracker] Could not save state: {e}", flush=True)

# ---------------------------------------------------------------------------
# Cluster API helpers
# ---------------------------------------------------------------------------

def _cid_str(raw) -> str:
    """Normalise CID — can be a string or an IPLD link dict {'/': 'Qm...'}."""
    if isinstance(raw, dict):
        return raw.get("/", "")
    return str(raw)


def get_pins():
    """Return list of GlobalPinInfo dicts from the cluster REST API.

    The cluster returns NDJSON (one JSON object per line) when there are
    multiple pins, a plain JSON array in some versions, or a single object.
    Handle all three.
    """
    url = f"{CLUSTER_API}/pins"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode()

    lines = [l.strip() for l in raw.strip().split("\n") if l.strip()]
    if not lines:
        return []

    # NDJSON: meerdere JSON-objecten, één per regel
    if lines[0].startswith("{") and lines[0].endswith("}"):
        return [json.loads(l) for l in lines if l.startswith("{")]

    # JSON array
    if raw.strip().startswith("["):
        data = json.loads(raw)
        return data if isinstance(data, list) else [data]

    # Single object
    if raw.strip().startswith("{"):
        return [json.loads(raw)]

    return []


def unpin_cid(cid: str) -> bool:
    """DELETE /pins/{cid} — returns True on success or 404 (already gone)."""
    url = f"{CLUSTER_API}/pins/{cid}"
    req = urllib.request.Request(url, method="DELETE")
    try:
        with urllib.request.urlopen(req, timeout=30):
            return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return True   # already unpinned, that's fine
        print(f"[tracker] DELETE {cid[:20]}... → HTTP {e.code}", flush=True)
        return False
    except Exception as e:
        print(f"[tracker] DELETE {cid[:20]}... → {e}", flush=True)
        return False

# ---------------------------------------------------------------------------
# Poll loop (runs in a background thread)
# ---------------------------------------------------------------------------

def poll_loop():
    load_state()

    while True:
        try:
            pins = get_pins()
        except Exception as e:
            print(f"[tracker] GET /pins failed: {e}", flush=True)
            time.sleep(POLL_INTERVAL)
            continue

        with state_lock:
            to_fail = []   # CIDs to unpin this round (avoid mutating set while iterating)

            # Aggregate counts for the /summary endpoint — computed in this same
            # pass over `pins` so a 200K-CID pinset is only iterated once per poll.
            counts = {"pinned": 0, "pinning": 0, "queued": 0, "error": 0}

            for pin in pins:
                cid = _cid_str(pin.get("cid", ""))
                peer_map = pin.get("peer_map", {})

                for info in peer_map.values():
                    status = info.get("status", "")
                    if status == "pinned":
                        counts["pinned"] += 1
                    elif status == "pinning":
                        counts["pinning"] += 1
                    elif status in ("queued", "pin_queued"):
                        counts["queued"] += 1
                    elif "error" in status:
                        counts["error"] += 1

                if not cid or cid in failed_cids:
                    continue

                # A CID is "in error" when ALL peers that have an opinion report error.
                # Peers that are "queued" or "pinning" don't count against the CID yet.
                statuses = {info.get("status", "") for info in peer_map.values()}
                error_peers = statuses & ERROR_STATUSES

                if error_peers and not (statuses - ERROR_STATUSES - {"unpinned"}):
                    # Every active peer is in error
                    error_counts[cid] = error_counts.get(cid, 0) + 1
                    count = error_counts[cid]
                    print(f"[tracker] {cid[:24]}… error {count}/{MAX_RETRIES}", flush=True)

                    if count >= MAX_RETRIES:
                        to_fail.append(cid)
                else:
                    # At least one peer is healthy → reset counter
                    if cid in error_counts:
                        error_counts.pop(cid)

            for cid in to_fail:
                print(f"[tracker] {cid[:24]}… reached {MAX_RETRIES} errors → unpinning", flush=True)
                if unpin_cid(cid):
                    failed_cids.add(cid)
                    error_counts.pop(cid, None)
                    print(f"[tracker] {cid[:24]}… unpinned and marked failed", flush=True)
                else:
                    print(f"[tracker] {cid[:24]}… unpin failed, will retry next poll", flush=True)

            summary.clear()
            summary.update(counts)
            summary["pin_count"] = len(pins)
            summary["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

            # Always persisted — /summary must stay useful across tracker restarts.
            save_state()

        time.sleep(POLL_INTERVAL)

# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence per-request logs; errors still go to stderr

    # --- GET ---
    def do_GET(self):
        if self.path in ("/failed-cids", "/failed-cids/"):
            with state_lock:
                body = json.dumps(sorted(failed_cids), indent=2).encode()
            self._json(200, body)

        elif self.path in ("/status", "/status/"):
            with state_lock:
                body = json.dumps({
                    "failed_count":   len(failed_cids),
                    "tracking_count": len(error_counts),
                    "max_retries":    MAX_RETRIES,
                    "poll_interval":  POLL_INTERVAL,
                    "error_counts":   dict(error_counts),
                }, indent=2).encode()
            self._json(200, body)

        elif self.path in ("/summary", "/summary/"):
            # Cached aggregate pin-status counts — never triggers a live cluster
            # broadcast. Computed once per poll cycle regardless of pinset size.
            with state_lock:
                body = json.dumps(dict(summary), indent=2).encode()
            self._json(200, body)

        elif self.path in ("/healthz", "/health"):
            self._json(200, b'{"status":"ok"}')

        else:
            self._json(404, b'{"error":"not found"}')

    # --- DELETE /failed-cids/{cid} → remove from failed list so it can be retried ---
    def do_DELETE(self):
        prefix = "/failed-cids/"
        if self.path.startswith(prefix):
            cid = self.path[len(prefix):].strip("/")
            if not cid:
                self._json(400, b'{"error":"missing cid"}')
                return
            with state_lock:
                if cid in failed_cids:
                    failed_cids.discard(cid)
                    save_state()
                    self._json(200, json.dumps({"removed": cid}).encode())
                else:
                    self._json(404, json.dumps({"error": "not in failed list"}).encode())
        else:
            self._json(404, b'{"error":"not found"}')

    def _json(self, code, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print(f"[tracker] cluster={CLUSTER_API}  poll={POLL_INTERVAL}s  "
          f"max_retries={MAX_RETRIES}  port={SERVE_PORT}", flush=True)

    t = threading.Thread(target=poll_loop, daemon=True)
    t.start()

    server = HTTPServer(("0.0.0.0", SERVE_PORT), Handler)
    print(f"[tracker] Listening on :{SERVE_PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("[tracker] Shutting down", flush=True)
        sys.exit(0)
