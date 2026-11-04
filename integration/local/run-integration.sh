#!/usr/bin/env bash
set -euo pipefail
backend=${1:?Usage: run-integration.sh postgrest|trino|starrocks|minilake}
case "$backend" in postgrest|trino|starrocks|minilake) ;; *) exit 2 ;; esac
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export OAUTHDB_FIXTURE="$backend"
project="oauthdb-${backend}-$(date +%s)-$$"
compose=(docker compose --project-name "$project" --project-directory "$root/integration/local"
  --file "$root/integration/local/compose.yml" --file "$root/integration/${backend}-keycloak/compose.yml")
cleanup() { "${compose[@]}" down --volumes --remove-orphans; }
trap cleanup EXIT
"${compose[@]}" config --quiet
if [[ ${OAUTHDB_SKIP_BUILD:-0} != 1 ]]; then
  builder=$(docker context show)
  if [[ ${OAUTHDB_SKIP_BASE_BUILD:-0} != 1 ]]; then
    docker build --builder "$builder" --target runner --tag shinyoauthdb-local-runner:1 "$root/integration/local"
  fi
  # The context's built-in builder can use CI's base image from the local image store.
  docker build --builder "$builder" --target tls --tag shinyoauthdb-local-tls:1 "$root/integration/local"
  if [[ "$backend" != postgrest ]]; then
    docker build --builder "$builder" --target runner --tag "shinyoauthdb-${backend}-runner:1" "$root/integration/${backend}-keycloak"
  fi
fi
services=(database tls-probe)
if [[ "$backend" == postgrest ]]; then services+=(https); fi
if ! "${compose[@]}" up --detach --wait --wait-timeout 240 "${services[@]}"; then
  # Startup precedes browser login; authentication/query logs are never exported.
  "${compose[@]}" logs --tail 1000 database
  exit 1
fi
"${compose[@]}" run --rm --no-deps test-runner
