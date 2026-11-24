#!/usr/bin/env bash
set -euo pipefail

output=$1
interval=${2:-1}
project=${COMPOSE_PROJECT_NAME:-scaling-lab}

printf 'timestamp_utc,container,cpu_percent,memory_usage,memory_percent,net_io,block_io\n' > "$output"
while true; do
  ids=$(docker ps -q --filter "label=com.docker.compose.project=${project}")
  if [[ -n "$ids" ]]; then
    docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}' $ids 2>/dev/null \
      | sed "s/^/$(date -u +%Y-%m-%dT%H:%M:%SZ),/" >> "$output" || true
  fi
  sleep "$interval"
done
