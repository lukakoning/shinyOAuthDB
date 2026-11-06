#!/usr/bin/env bash
set -euo pipefail
sed -i 's/-Xmx8192m/-Xmx1024m/' /data/deploy/starrocks/fe/conf/fe.conf
cat >> /data/deploy/starrocks/fe/conf/fe.conf <<'EOF'
ssl_keystore_location = /fixtures/tls/server.p12
ssl_keystore_password = fixture-keystore
ssl_key_password = fixture-keystore
ssl_force_secure_transport = true
EOF
echo 'mem_limit = 1024m' >> /data/deploy/starrocks/be/conf/be.conf
exec /data/deploy/entrypoint.sh
