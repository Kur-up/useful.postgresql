#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Copy .env.example and fill in the values." >&2
  exit 1
fi

if [[ ! -f configs/pgbouncer/tls/server.crt ]]; then
  echo "TLS certificates not found, generating..."
  bash "$(dirname "$0")/gen-certs.sh"
fi

set -a
source .env
set +a

if [[ ! -f configs/pgbouncer/userlist.txt ]]; then
  echo "Generating configs/pgbouncer/userlist.txt..."
  printf '"%s" "%s"\n' "$POSTGRESQL_USER" "$POSTGRESQL_PASSWORD" \
    > configs/pgbouncer/userlist.txt
  chown 65532:65532 configs/pgbouncer/userlist.txt
  chmod 600 configs/pgbouncer/userlist.txt
fi

if [[ ! -f configs/pgbouncer/pgbouncer.ini ]]; then
  echo "Generating configs/pgbouncer/pgbouncer.ini..."
  envsubst \
    '${POSTGRESQL_DB} ${POSTGRESQL_USER}
     ${PGBOUNCER_POOL_MODE}
     ${PGBOUNCER_MAX_CLIENT_CONN} ${PGBOUNCER_DEFAULT_POOL_SIZE}
     ${PGBOUNCER_MIN_POOL_SIZE} ${PGBOUNCER_RESERVE_POOL_SIZE}
     ${PGBOUNCER_RESERVE_POOL_TIMEOUT} ${PGBOUNCER_TLS_SSLMODE}' \
    < configs/pgbouncer/pgbouncer.ini.template \
    > configs/pgbouncer/pgbouncer.ini
  chown 65532:65532 configs/pgbouncer/pgbouncer.ini
  chmod 600 configs/pgbouncer/pgbouncer.ini
fi

mkdir -p data/postgresql
chown 70:70 data/postgresql

docker compose up -d "$@"
