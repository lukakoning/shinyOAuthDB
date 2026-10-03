#!/usr/bin/env bash
set -euo pipefail

tls_dir="${1:-/fixture-tls}"
mkdir -p "$tls_dir"

# Reuse valid fixture certificates so restarting containers preserves trust.
if [[ -f "$tls_dir/ca-cert.pem" && -f "$tls_dir/server-cert.pem" && -f "$tls_dir/server-key.pem" ]]; then
  openssl verify -CAfile "$tls_dir/ca-cert.pem" "$tls_dir/server-cert.pem"
  openssl x509 -checkend 3600 -noout -in "$tls_dir/server-cert.pem"
  exit 0
fi

umask 077
openssl req -new -x509 -nodes -newkey rsa:3072 -sha256 -days 30 \
  -subj '/CN=shinyOAuthDB isolated fixture CA' \
  -keyout "$tls_dir/ca-key.pem" -out "$tls_dir/ca-cert.pem" \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'

openssl req -new -nodes -newkey rsa:2048 -sha256 -subj '/CN=localhost' \
  -keyout "$tls_dir/server-key.pem" -out "$tls_dir/server.csr"

cat > "$tls_dir/server-ext.cnf" <<'EOF'
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

openssl x509 -req -sha256 -days 30 -in "$tls_dir/server.csr" \
  -CA "$tls_dir/ca-cert.pem" -CAkey "$tls_dir/ca-key.pem" -CAcreateserial \
  -extfile "$tls_dir/server-ext.cnf" -out "$tls_dir/server-cert.pem"

chmod 644 "$tls_dir/ca-cert.pem" "$tls_dir/server-cert.pem"
chmod 600 "$tls_dir/server-key.pem" "$tls_dir/ca-key.pem"

# Keycloak's pinned image runs as UID 1000. PostgreSQL copies its own private key.
chown 1000:0 "$tls_dir/server-key.pem"

openssl verify -CAfile "$tls_dir/ca-cert.pem" "$tls_dir/server-cert.pem"
rm "$tls_dir/server.csr"
