#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
install -m 644 /fixtures/tls/ca-cert.pem /usr/local/share/ca-certificates/oauthdb-demo.crt
update-ca-certificates >/dev/null
exec "$@"
