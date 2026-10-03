#!/usr/bin/env bash
set -euo pipefail

install -m 644 /fixture-tls/ca-cert.pem /usr/local/share/ca-certificates/oauthdb-fixture.crt
update-ca-certificates >/dev/null

install -d -o postgres -g postgres -m 700 "$PGDATA" /run/oauthdb-tls
install -d -o postgres -g postgres -m 755 /var/run/postgresql
install -o postgres -g postgres -m 600 /fixture-tls/server-key.pem /run/oauthdb-tls/server-key.pem
install -o postgres -g postgres -m 644 /fixture-tls/server-cert.pem /run/oauthdb-tls/server-cert.pem

# Bootstrap over the local socket before exposing the TLS-only fixture server.
if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
  runuser -u postgres -- initdb --pgdata="$PGDATA" --auth-local=peer --auth-host=reject --encoding=UTF8 --locale=C.UTF-8
  runuser -u postgres -- pg_ctl -D "$PGDATA" -o "-c listen_addresses='' -c unix_socket_directories='/var/run/postgresql'" -w start
  trap 'runuser -u postgres -- pg_ctl -D "$PGDATA" -m immediate -w stop || true' EXIT

  runuser -u postgres -- psql --no-psqlrc --host=/var/run/postgresql --username=postgres --dbname=postgres \
    --file=/docker-entrypoint-initdb.d/01-fixture.sql

  runuser -u postgres -- pg_ctl -D "$PGDATA" -m fast -w stop
  trap - EXIT
fi

exec runuser -u postgres -- postgres -D "$PGDATA" -c config_file=/etc/oauthdb-fixture/postgresql.conf
