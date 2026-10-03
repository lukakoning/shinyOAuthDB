#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

project="${OAUTHDB_COMPOSE_PROJECT:-shinyoauthdb-postgres-keycloak-$(date +%s)-$$}"
if [[ ! "$project" =~ ^shinyoauthdb-postgres-keycloak(-[a-z0-9_-]+)?$ ]]; then
  echo 'OAUTHDB_COMPOSE_PROJECT must use the isolated shinyoauthdb-postgres-keycloak prefix.' >&2
  exit 2
fi

command -v docker >/dev/null
docker info >/dev/null
mkdir -p .generated
compose=(docker compose --project-name "$project" --file compose.yml)

cleanup() {
  local result=$?
  trap - EXIT INT TERM

  if [[ "${OAUTHDB_KEEP_FIXTURE:-0}" != 1 ]]; then
    # These names are scoped by Compose to this explicitly isolated project.
    if ! "${compose[@]}" down --volumes --remove-orphans >/dev/null; then
      if [[ "$result" == 0 ]]; then result=1; fi
    fi
  else
    printf 'Kept fixture project: %s\n' "$project"
    printf 'Cleanup: docker compose --project-name %s --file %q down --volumes\n' "$project" "$script_dir/compose.yml"
  fi

  exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${compose[@]}" config --quiet
"${compose[@]}" build postgres test-runner
"${compose[@]}" up --detach --wait --wait-timeout 240 postgres

if [[ "${OAUTHDB_PLAYGROUND:-0}" == 1 ]]; then
  "${compose[@]}" run --rm --no-deps test-runner Rscript integration/postgres-keycloak/run-tests.R --playground
else
  "${compose[@]}" run --rm --no-deps test-runner
fi
