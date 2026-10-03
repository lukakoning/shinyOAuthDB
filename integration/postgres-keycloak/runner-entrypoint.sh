#!/usr/bin/env bash
set -euo pipefail
install -m 644 /fixtures/tls/ca-cert.pem /usr/local/share/ca-certificates/oauthdb-fixture.crt
update-ca-certificates >/dev/null
mkdir -p /root/.pki/nssdb /results
if [[ ! -f /root/.pki/nssdb/cert9.db ]]; then
  certutil -N -d sql:/root/.pki/nssdb --empty-password
fi
certutil -A -d sql:/root/.pki/nssdb -n oauthdb-fixture -t 'C,,' -i /fixtures/tls/ca-cert.pem
# run-tests.R installs the current mounted checkouts into its temporary library.
# Existing host libraries and packages never change.
exec "$@"
