#!/usr/bin/env bash
set -euo pipefail
keytool -importcert -noprompt -trustcacerts -alias oauthdb-fixture \
  -file /fixtures/tls/ca-cert.pem -cacerts -storepass changeit
exec /usr/lib/trino/bin/launcher run --etc-dir /etc/trino
