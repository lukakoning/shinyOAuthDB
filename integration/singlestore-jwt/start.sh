#!/bin/bash
set -euo pipefail

tar -xzf /server/data.tgz -C /data
for config in /data/master/memsql.cnf /data/leaf/memsql.cnf; do
  cat >> "$config" <<'CONFIG'
ssl_cert = /fixture/server.pem
ssl_key = /fixture/server.key
ssl_ca = /fixture/ca.pem
CONFIG
done

python3 -m http.server 18082 --bind 127.0.0.1 --directory /fixture >/tmp/jwks.log 2>&1 &
exec /scripts/start.sh
