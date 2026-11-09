#!/bin/sh
set -eu
mkdir -p /tmp/azure-postgres-tls
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout /tmp/azure-postgres-tls/server.key \
  -out /tmp/azure-postgres-tls/server.crt \
  -subj /CN=localhost -addext subjectAltName=DNS:localhost,IP:127.0.0.1
chown -R postgres:postgres /tmp/azure-postgres-tls
chmod 600 /tmp/azure-postgres-tls/server.key
cp /tmp/azure-postgres-tls/server.crt /out/ca.pem
printf '%s\n' 'local all all trust' 'hostssl all all all password' > /tmp/azure-postgres-pg_hba.conf
exec docker-entrypoint.sh postgres \
  -c ssl=on \
  -c ssl_key_file=/tmp/azure-postgres-tls/server.key \
  -c ssl_cert_file=/tmp/azure-postgres-tls/server.crt \
  -c hba_file=/tmp/azure-postgres-pg_hba.conf
