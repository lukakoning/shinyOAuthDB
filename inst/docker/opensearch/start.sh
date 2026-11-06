#!/usr/bin/env bash
set -euo pipefail
cp /state/opensearch.yml /usr/share/opensearch/config/opensearch.yml
cp /state/node.pem /state/node-key.pem /usr/share/opensearch/config/
chmod 600 /usr/share/opensearch/config/node-key.pem
cp /state/security/* /usr/share/opensearch/config/opensearch-security/
exec /usr/share/opensearch/opensearch-docker-entrypoint.sh opensearch
