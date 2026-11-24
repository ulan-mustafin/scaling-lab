#!/usr/bin/env bash
set -euo pipefail

strategy=${1:?"Strategy required: horizontal or vertical"}
level=${2:?"Level required: 1, 2, 3, or 4"}
runs=${3:-3}
vus=${4:-25}
duration=${5:-60s}
iterations=${6:-50000}
port=${HOST_PORT:-18080}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

case "$strategy" in
  horizontal) replicas=$level; cpus=1.0; memory=512m ;;
  vertical) replicas=1; cpus=$level; memory="$((level * 512))m" ;;
  *) echo "Strategy must be horizontal or vertical." >&2; exit 2 ;;
esac
[[ "$level" =~ ^[1-4]$ ]] || { echo "Level must be 1 through 4." >&2; exit 2; }
command -v docker >/dev/null || { echo "Docker is required." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon is not running." >&2; exit 1; }

env_file=""
metrics_pid=""
docker_config=""
cleanup() {
  if [[ -n "$metrics_pid" ]]; then
    kill "$metrics_pid" 2>/dev/null || true
    wait "$metrics_pid" 2>/dev/null || true
    metrics_pid=""
  fi
  [[ -n "$env_file" ]] && "${compose_cmd[@]}" --env-file "$env_file" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
remove_docker_config() {
  if [[ -n "$docker_config" ]]; then
    rm -rf "$docker_config"
    docker_config=""
  fi
}
on_exit() {
  cleanup
  remove_docker_config
}
trap on_exit EXIT INT TERM

k6_image="grafana/k6:0.55.0"
docker_config=$(mktemp -d "${TMPDIR:-/tmp}/scaling-lab-docker-config.XXXXXX")
printf '{"auths":{}}\n' > "$docker_config/config.json"
export DOCKER_CONFIG="$docker_config"
docker_cmd=(docker --config "$docker_config")
compose_cmd=("${docker_cmd[@]}" compose)
"${docker_cmd[@]}" image inspect "$k6_image" >/dev/null 2>&1 || "${docker_cmd[@]}" pull "$k6_image"
"${compose_cmd[@]}" build

for run in $(seq 1 "$runs"); do
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  output="results/${strategy}-${level}/run-${run}-${stamp}"
  mkdir -p "$output"
  env_file="$output/compose.env"
  cat > "$env_file" <<EOF
APP_CPUS=$cpus
APP_MEMORY=$memory
HOST_PORT=$port
EOF
  cat > "$output/config.json" <<EOF
{"strategy":"$strategy","level":$level,"replicas":$replicas,"cpu_per_container":$cpus,"memory_per_container":"$memory","vus":$vus,"duration":"$duration","iterations":$iterations,"run":$run,"timestamp_utc":"$stamp"}
EOF

  trap on_exit EXIT INT TERM
  cleanup
  "${compose_cmd[@]}" --env-file "$env_file" up -d --scale "app=$replicas"
  for _ in $(seq 1 30); do
    curl --fail --silent "http://localhost:${port}/health" >/dev/null && break
    sleep 2
  done
  curl --fail --silent "http://localhost:${port}/health" >/dev/null || { echo "Service did not become healthy." >&2; exit 1; }

  ./scripts/collect_metrics.sh "$output/docker-stats.csv" &
  metrics_pid=$!
  "${docker_cmd[@]}" run --rm --network scaling-lab-network \
    -e BASE_URL=http://nginx -e VUS="$vus" -e DURATION="$duration" -e ITERATIONS="$iterations" \
    -v "$root/load-tests:/scripts:ro" -v "$root/$output:/results" \
    "$k6_image" run --summary-export=/results/k6-summary.json /scripts/scaling-test.js
  kill "$metrics_pid" 2>/dev/null || true
  wait "$metrics_pid" 2>/dev/null || true
  metrics_pid=""
  cleanup
  echo "Completed: $output"
done
