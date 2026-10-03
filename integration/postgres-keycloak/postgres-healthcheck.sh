#!/usr/bin/env bash
set -euo pipefail
# LOAD catches unresolved validator symbols before the browser test container
# starts; a custom GUC placeholder alone cannot prove the module is loadable.
result="$(runuser -u postgres -- psql --no-psqlrc --quiet --host=/var/run/postgresql \
  --username=postgres --dbname=oauthdb_fixture --tuples-only --no-align \
  --command="LOAD 'pg_oidc_validator'; SELECT current_setting('pg_oidc_validator.expected_audience') = 'postgres-fixture' AND (SELECT count(*) FROM public.visible_rows) = 4" 2>/dev/null)"
[[ "$result" == t ]]
