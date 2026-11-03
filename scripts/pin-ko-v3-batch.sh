#!/bin/bash
# Pin KOv3 curated batches with explicit allocations.
#
# Defaults pin batches 09-21 to vernis-artbox + zomi + rudeberry-pi and never
# to the coordinator (DRL Cluster), which must not store content.
#
# Usage:
#   bash scripts/pin-ko-v3-batch.sh
#   START_BATCH=09 END_BATCH=21 bash scripts/pin-ko-v3-batch.sh
#   ALLOCATIONS="<peerA>,<peerB>" START_BATCH=31 END_BATCH=63 bash scripts/pin-ko-v3-batch.sh
#   DRY_RUN=1 START_BATCH=09 END_BATCH=09 bash scripts/pin-ko-v3-batch.sh
#
# Env:
#   START_BATCH / END_BATCH   zero-padded batch range (default 09 .. 21)
#   ALLOCATIONS               comma-separated peer IDs; empty = let the cluster allocator decide
#   REPL_MIN / REPL_MAX       only used when ALLOCATIONS is empty (default 2 / 3)
#   BATCH_SIZE / PAUSE_SECONDS  throttle between pins (default 100 / 15)
#   BATCH_DIR                 default data/batches
#   DRY_RUN=1                 resolve todo lists and print them, pin nothing

set -uo pipefail

CLUSTER_CTL=${CLUSTER_CTL:-docker exec cluster ipfs-cluster-ctl}
IPFS_CTL=${IPFS_CTL:-docker exec ipfs ipfs}

COORDINATOR_PEER_ID=12D3KooWMRpaSMLHj3aoJqfxDMErRfu64HeHbwTttUynofsuBbzd
DEFAULT_ALLOCATIONS=12D3KooWFnsoGcDhPyRu1vrvTyXzKXgXjBhcNAg3E5p5fVAsnE2o,12D3KooWJinwFX9Cjud73WjAmeh2g4JR789jPR2wKaYHzoSwaQLC,12D3KooWPpZYgopCx1EweNMQPHd5HP4n1UmS37mrWFCLK7E38RRe

START_BATCH=${START_BATCH:-09}
END_BATCH=${END_BATCH:-21}
ALLOCATIONS=${ALLOCATIONS-$DEFAULT_ALLOCATIONS}
REPL_MIN=${REPL_MIN:-2}
REPL_MAX=${REPL_MAX:-3}
BATCH_SIZE=${BATCH_SIZE:-100}
PAUSE_SECONDS=${PAUSE_SECONDS:-15}
BATCH_DIR=${BATCH_DIR:-data/batches}
DRY_RUN=${DRY_RUN:-0}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf '%s\n' "$*" >&2; exit 1; }

if [ -n "$ALLOCATIONS" ]; then
  case ",$ALLOCATIONS," in
    *",$COORDINATOR_PEER_ID,"*) fail "ALLOCATIONS contains the coordinator peer ($COORDINATOR_PEER_ID); refusing to pin to DRL Cluster" ;;
  esac
fi

command -v jq >/dev/null || fail "jq is required"
$CLUSTER_CTL id >/dev/null 2>&1 || fail "cannot reach the cluster via: $CLUSTER_CTL"
$IPFS_CTL id >/dev/null 2>&1 || fail "cannot reach kubo via: $IPFS_CTL"

pinned_v1() { $CLUSTER_CTL pin ls 2>/dev/null | awk '{print $1}' | sort -u; }

pinned_v1 > "$TMP/pinned_before.txt"
DRL_BEFORE=$(grep -c "$COORDINATOR_PEER_ID" <($CLUSTER_CTL pin ls 2>/dev/null) || true)

echo "=== KOv3 pinning: batch ${START_BATCH}..${END_BATCH} ==="
echo "allocations : ${ALLOCATIONS:-<cluster allocator>}"
if [ -z "$ALLOCATIONS" ]; then
  echo "replication : min=${REPL_MIN} max=${REPL_MAX}"
fi
echo "pins before : $(wc -l < "$TMP/pinned_before.txt" | tr -d ' ')"
echo "DRL pins    : ${DRL_BEFORE}"
if [ "$DRY_RUN" = "1" ]; then
  echo "mode        : DRY RUN"
fi
echo

overall_ok=0
overall_skipped=0
overall_failed=0
failed_batches=()

for i in $(seq "$START_BATCH" "$END_BATCH"); do
  n=$(printf '%02d' "$i")
  file=$(ls "$BATCH_DIR"/curated-cids-ko-v3-batch"${n}".json 2>/dev/null | head -1)
  if [ -z "$file" ]; then
    echo "!! batch $n: no curated-cids-ko-v3-batch${n}.json in $BATCH_DIR, skipped"
    failed_batches+=("$n(missing-file)")
    continue
  fi

  total=$(jq 'length' "$file")
  jq -r '.[]' "$file" > "$TMP/batch_${n}_v0.txt"

  if ! xargs -n 200 $IPFS_CTL cid base32 < "$TMP/batch_${n}_v0.txt" 2>/dev/null | sort -u > "$TMP/batch_${n}_v1.txt"; then
    echo "!! batch $n: CIDv0 -> CIDv1 conversion failed"
    failed_batches+=("$n(cid-convert)")
    continue
  fi
  if [ ! -s "$TMP/batch_${n}_v1.txt" ]; then
    echo "!! batch $n: conversion produced no CIDs"
    failed_batches+=("$n(cid-convert-empty)")
    continue
  fi

  comm -12 "$TMP/batch_${n}_v1.txt" "$TMP/pinned_before.txt" > "$TMP/batch_${n}_skip.txt"
  comm -23 "$TMP/batch_${n}_v1.txt" "$TMP/pinned_before.txt" > "$TMP/batch_${n}_todo.txt"

  skipped=$(wc -l < "$TMP/batch_${n}_skip.txt" | tr -d ' ')
  todo=$(wc -l < "$TMP/batch_${n}_todo.txt" | tr -d ' ')
  echo "=== batch $n: ${total} CIDs, ${skipped} already pinned, ${todo} to pin ==="

  if [ "$DRY_RUN" = "1" ]; then
    cat "$TMP/batch_${n}_todo.txt"
    overall_skipped=$((overall_skipped + skipped))
    echo
    continue
  fi

  i=0
  ok=0
  bad=0
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    i=$((i + 1))
    if [ -n "$ALLOCATIONS" ]; then
      $CLUSTER_CTL pin add "$cid" --allocations "$ALLOCATIONS" >/dev/null 2>&1
      rc=$?
    else
      $CLUSTER_CTL pin add "$cid" --replication-min "$REPL_MIN" --replication-max "$REPL_MAX" >/dev/null 2>&1
      rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
      ok=$((ok + 1))
    else
      bad=$((bad + 1))
      echo "  FAIL $cid"
    fi
    if [ $((i % BATCH_SIZE)) -eq 0 ] && [ "$i" -lt "$todo" ]; then
      echo "  ${i}/${todo} (ok=${ok} fail=${bad}) - pause ${PAUSE_SECONDS}s"
      sleep "$PAUSE_SECONDS"
    fi
  done < "$TMP/batch_${n}_todo.txt"

  pinned_v1 > "$TMP/pinned_after.txt"
  confirmed=$(comm -12 "$TMP/batch_${n}_v1.txt" "$TMP/pinned_after.txt" | wc -l | tr -d ' ')
  drl_now=$(grep -c "$COORDINATOR_PEER_ID" <($CLUSTER_CTL pin ls 2>/dev/null) || true)

  echo "batch $n done: ok=${ok} fail=${bad} confirmed_pinned=${confirmed}/${total} drl_pins=${drl_now}"

  if [ "$drl_now" -gt "$DRL_BEFORE" ]; then
    fail "DRL Cluster received $((drl_now - DRL_BEFORE)) new pins during batch $n - aborting"
  fi

  overall_ok=$((overall_ok + ok))
  overall_skipped=$((overall_skipped + skipped))
  overall_failed=$((overall_failed + bad))
  if [ "$confirmed" -ne "$total" ]; then
    failed_batches+=("$n(${confirmed}/${total})")
  fi
  echo
done

echo "=== summary ==="
echo "pinned      : ${overall_ok}"
echo "skipped     : ${overall_skipped}"
echo "failed      : ${overall_failed}"
echo "incomplete  : ${failed_batches[*]:-none}"

if [ "$overall_failed" -gt 0 ] || [ "${#failed_batches[@]}" -gt 0 ]; then
  exit 1
fi
