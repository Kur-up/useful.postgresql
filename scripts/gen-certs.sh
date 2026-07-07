#!/usr/bin/env bash
set -euo pipefail

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
  shift
fi

cd "$(dirname "$0")/.."

OUT_DIR="configs/pgbouncer/tls"
mkdir -p "$OUT_DIR"

if [[ -f "$OUT_DIR/ca.crt" && -f "$OUT_DIR/server.crt" ]] && [[ "$FORCE" == false ]]; then
  echo "Certificates already exist in $OUT_DIR. Use --force to regenerate."
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  SERVER_CN="$1"
else
  read -r -p "Server CN (hostname or IP clients will connect to, e.g. 10.0.0.5): " SERVER_CN
fi
: "${SERVER_CN:?CN cannot be empty}"

DAYS_CA=3650
DAYS_CERT=825

echo ""
echo "Generating CA and server certificate for CN=${SERVER_CN} ..."

openssl genrsa -out "$OUT_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$OUT_DIR/ca.key" \
  -sha256 \
  -days "$DAYS_CA" \
  -subj "/CN=PgBouncer-CA/O=Infrastructure" \
  -out "$OUT_DIR/ca.crt"

openssl genrsa -out "$OUT_DIR/server.key" 4096

if [[ "$SERVER_CN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SAN_EXT="subjectAltName=IP:${SERVER_CN},IP:127.0.0.1"
else
  SAN_EXT="subjectAltName=DNS:${SERVER_CN},IP:127.0.0.1"
fi

openssl req -new \
  -key "$OUT_DIR/server.key" \
  -subj "/CN=${SERVER_CN}/O=Infrastructure" \
  -out "$OUT_DIR/server.csr"

openssl x509 -req \
  -in "$OUT_DIR/server.csr" \
  -CA "$OUT_DIR/ca.crt" \
  -CAkey "$OUT_DIR/ca.key" \
  -CAcreateserial \
  -days "$DAYS_CERT" \
  -sha256 \
  -extfile <(echo "$SAN_EXT") \
  -out "$OUT_DIR/server.crt"

rm -f "$OUT_DIR/server.csr" "$OUT_DIR/ca.srl"

chmod 600 "$OUT_DIR/ca.key"
chown 65532:65532 "$OUT_DIR/server.key" && chmod 600 "$OUT_DIR/server.key"
chmod 644 "$OUT_DIR/ca.crt" "$OUT_DIR/server.crt"

echo ""
echo "Done. Files written to $OUT_DIR:"
echo "  ca.key      — CA private key       (secret, root-only)"
echo "  ca.crt      — CA certificate       (distribute to clients for verification)"
echo "  server.key  — server private key   (secret, readable by PgBouncer)"
echo "  server.crt  — server certificate   (served by PgBouncer)"
echo ""
echo "Certificate validity:"
openssl x509 -in "$OUT_DIR/server.crt" -noout -dates
echo ""
echo "Subject Alternative Names:"
openssl x509 -in "$OUT_DIR/server.crt" -noout -ext subjectAltName
