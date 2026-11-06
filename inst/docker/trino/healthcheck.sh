#!/usr/bin/env bash
set -euo pipefail
info=$(curl --fail --silent --cacert /fixtures/tls/ca-cert.pem https://localhost:18444/v1/info)
[[ $info == *'"starting":false'* ]]
