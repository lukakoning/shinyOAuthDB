#!/usr/bin/env bash
set -euo pipefail
directory=/fixtures/tls
mkdir -p "$directory"
umask 077
openssl req -new -x509 -nodes -newkey rsa:3072 -sha256 -days 2 \
  -subj '/CN=shinyOAuthDB local integration CA' \
  -keyout "$directory/ca-key.pem" -out "$directory/ca-cert.pem" \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -new -nodes -newkey rsa:2048 -sha256 -subj '/CN=localhost' \
  -keyout "$directory/server-key.pem" -out "$directory/server.csr"
cat > "$directory/extensions.cnf" <<'EOF'
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -sha256 -days 2 -in "$directory/server.csr" \
  -CA "$directory/ca-cert.pem" -CAkey "$directory/ca-key.pem" -CAcreateserial \
  -extfile "$directory/extensions.cnf" -out "$directory/server-cert.pem"
cat "$directory/server-cert.pem" "$directory/server-key.pem" > "$directory/server.pem"
openssl pkcs12 -export -name localhost -in "$directory/server-cert.pem" \
  -inkey "$directory/server-key.pem" -certfile "$directory/ca-cert.pem" \
  -out "$directory/server.p12" -passout pass:fixture-keystore
chmod 644 "$directory/ca-cert.pem" "$directory/server-cert.pem"
chown 1000:0 "$directory/server-key.pem" "$directory/server.pem" "$directory/server.p12"
chmod 640 "$directory/server-key.pem" "$directory/server.pem" "$directory/server.p12"
openssl verify -CAfile "$directory/ca-cert.pem" "$directory/server-cert.pem"
