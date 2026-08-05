#!/usr/bin/env bash
# Print the live state of all three environments.
# Same image tag across environments = promotion worked.
set -uo pipefail

printf "%-9s %-6s %-9s %-44s %s\n" ENV PODS PORT VERSION STATUS
printf "%-9s %-6s %-9s %-44s %s\n" --- ---- ---- ------- ------

for ns in dev staging prod; do
  case "$ns" in
    dev)     port=30080 ;;
    staging) port=30081 ;;
    prod)    port=30082 ;;
  esac

  pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c Running)
  body=$(curl -s -m 3 "localhost:${port}/health" 2>/dev/null)

  if [ -z "$body" ]; then
    printf "%-9s %-6s %-9s %-44s %s\n" "$ns" "$pods" "$port" "-" "UNREACHABLE"
    continue
  fi

  version=$(printf '%s' "$body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  status=$(printf '%s' "$body" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
  printf "%-9s %-6s %-9s %-44s %s\n" "$ns" "$pods" "$port" "$version" "$status"
done
