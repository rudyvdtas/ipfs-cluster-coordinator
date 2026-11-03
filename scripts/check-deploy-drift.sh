#!/bin/bash
# Detects drift between the directory that actually runs the compose stack and
# the git working copy. Run this before any deploy or pull.
#
# Usage:
#   bash scripts/check-deploy-drift.sh
#   PROJECT=other-stack bash scripts/check-deploy-drift.sh
#
# Exit codes: 0 = live dir is a git working copy and up to date
#             1 = drift (no git in live dir, behind origin, or dirty)
#             2 = could not determine the live directory

set -u

PROJECT=${PROJECT:-ipfs-cluster-coordinator}
LIVE_HINT=${LIVE_HINT:-/root/ipfs-cluster-coordinator}
REPO_HINT=${REPO_HINT:-/opt/ipfs-cluster-coordinator}

say() { printf '%s\n' "$*"; }
rc=0

if ! docker compose ls --format json >/dev/null 2>&1; then
  say "FAIL: 'docker compose ls --format json' is not available (compose v2 required)"
  exit 2
fi

config_files=$(docker compose ls --format json 2>/dev/null \
  | jq -r --arg p "$PROJECT" '.[] | select(.Name==$p) | .ConfigFiles' 2>/dev/null \
  | cut -d, -f1)

if [ -z "$config_files" ]; then
  say "FAIL: compose project '$PROJECT' is not running"
  exit 2
fi

live_dir=$(dirname "$config_files")

say "project        : $PROJECT"
say "config files   : $config_files"
say "live directory : $live_dir"
say

if [ -d "$live_dir/.git" ]; then
  say "git in live dir: yes"
  if git -C "$live_dir" fetch --quiet origin 2>/dev/null; then
    branch=$(git -C "$live_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    behind=$(git -C "$live_dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo "?")
    ahead=$(git -C "$live_dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "?")
    dirty=$(git -C "$live_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    say "branch         : $branch"
    say "behind origin  : $behind"
    say "ahead of origin: $ahead"
    say "dirty files    : $dirty"
    if [ "$behind" != "0" ]; then
      say "WARN: live dir is $behind commit(s) behind origin/$branch - pull before deploying"
      rc=1
    fi
    if [ "$ahead" != "0" ]; then
      say "WARN: live dir has $ahead commit(s) that are not pushed to origin"
      rc=1
    fi
  else
    say "WARN: could not fetch origin (network or credentials)"
    rc=1
  fi
else
  say "git in live dir: NO"
  say "WARN: the directory running the stack is not a git working copy."
  say "      Edits there never reach git and 'git pull' elsewhere does not apply them."
  rc=1
fi

say
say "docker-compose.yaml copies on this host:"
for d in "$LIVE_HINT" "$REPO_HINT"; do
  [ -f "$d/docker-compose.yaml" ] || continue
  marker=""
  [ "$d" = "$live_dir" ] && marker=" <- LIVE"
  [ -d "$d/.git" ] && marker="$marker [git]"
  say "  $d$marker"
done

say
if [ "$rc" -eq 0 ]; then
  say "OK: live dir is the git working copy and is up to date"
fi

exit "$rc"
