#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
install -m 644 /fixtures/tls/ca-cert.pem /usr/local/share/ca-certificates/oauthdb-fixture.crt
update-ca-certificates >/dev/null
mkdir -p /root/.pki/nssdb /results
certutil -N -d sql:/root/.pki/nssdb --empty-password
certutil -A -d sql:/root/.pki/nssdb -n oauthdb-fixture -t 'C,,' -i /fixtures/tls/ca-cert.pem
chmod +x /usr/local/bin/fixture-chromium
exec "$@"
