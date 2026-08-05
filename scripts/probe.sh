#!/usr/bin/env bash
# Continuously probe an environment during a rollout and count failures.
# Demonstrates that maxUnavailable: 0 plus the preStop hook keeps the
# service available while pods are replaced.
#
#   ./scripts/probe.sh [port]   default 30080 (dev)
set -uo pipefail

PORT="${1:-30080}"
ok=0
fail=0
last=""

trap 'printf "\n\nRESULT  ok=%d  failed=%d\n" "$ok" "$fail"; exit 0' INT

printf "probing localhost:%s/health  (ctrl-c to stop)\n\n" "$PORT"

while true; do
  version=$(curl -s -m 2 -D- -o /dev/null "localhost:${PORT}/health" 2>/dev/null \
            | awk 'tolower($1) ~ /^x-app-version:/ {print $2}' | tr -d '\r')

  if [ -n "$version" ]; then
    ok=$((ok + 1))
    if [ "$version" != "$last" ]; then
      printf "\n[%s] serving %s\n" "$(date +%H:%M:%S)" "$version"
      last="$version"
    fi
  else
    fail=$((fail + 1))
    printf "\n[%s] REQUEST FAILED\n" "$(date +%H:%M:%S)"
  fi

  printf "\r  ok=%-6d failed=%-4d" "$ok" "$fail"
  sleep 0.5
done
