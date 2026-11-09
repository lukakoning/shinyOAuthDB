#!/bin/bash
set -euo pipefail
mkdir -p /certs /out
/cockroach/cockroach cert create-ca --certs-dir=/certs --ca-key=/certs/ca.key
/cockroach/cockroach cert create-node localhost 127.0.0.1 --certs-dir=/certs --ca-key=/certs/ca.key
/cockroach/cockroach cert create-client root --certs-dir=/certs --ca-key=/certs/ca.key
cp /certs/ca.crt /out/ca.crt
exec /cockroach/cockroach start-single-node --certs-dir=/certs \
  --listen-addr=0.0.0.0:26257 --http-addr=127.0.0.1:8080 \
  --store=type=mem,size=1GiB --cache=64MiB --max-sql-memory=64MiB
