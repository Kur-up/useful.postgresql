#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <extension-name>" >&2
  echo "" >&2
  echo "  Place extension files in extensions/ before running:" >&2
  echo "    extensions/lib/<name>.so    — shared library" >&2
  echo "    extensions/<name>.control   — extension metadata" >&2
  echo "    extensions/<name>--*.sql    — SQL scripts" >&2
  exit 1
fi

EXT_NAME="$1"
cd "$(dirname "$0")/.."

if [[ ! -f runtime/.initialized ]]; then
  echo "ERROR: runtime/ is not initialised. Run ./scripts/up.sh first." >&2
  exit 1
fi

echo "Installing extension: ${EXT_NAME}"

if [[ -f "extensions/lib/${EXT_NAME}.so" ]]; then
  echo "  → runtime/lib/${EXT_NAME}.so"
  cp "extensions/lib/${EXT_NAME}.so" runtime/lib/
  chown 70:70 "runtime/lib/${EXT_NAME}.so"
fi

if [[ -f "extensions/${EXT_NAME}.control" ]]; then
  echo "  → runtime/ext/${EXT_NAME}.control"
  # Normalise module_pathname to $libdir regardless of how the file was built.
  sed "s|module_pathname = '[^']*'|module_pathname = '\$libdir/${EXT_NAME}'|" \
    "extensions/${EXT_NAME}.control" > "runtime/ext/${EXT_NAME}.control"
  chown 70:70 "runtime/ext/${EXT_NAME}.control"
fi

copied_sql=0
for sqlfile in extensions/"${EXT_NAME}"--*.sql; do
  [[ -f "$sqlfile" ]] || continue
  fname=$(basename "$sqlfile")
  echo "  → runtime/ext/${fname}"
  cp "$sqlfile" "runtime/ext/${fname}"
  chown 70:70 "runtime/ext/${fname}"
  (( copied_sql++ )) || true
done

if [[ $copied_sql -eq 0 ]] && [[ ! -f "extensions/${EXT_NAME}.control" ]] && [[ ! -f "extensions/lib/${EXT_NAME}.so" ]]; then
  echo "ERROR: no files found for extension '${EXT_NAME}' in extensions/" >&2
  exit 1
fi

echo ""
echo "Done. Create the extension in PostgreSQL:"
echo "  docker compose exec postgresql psql -U <POSTGRESQL_USER> -d <POSTGRESQL_DB> \\"
echo "    -c \"CREATE EXTENSION IF NOT EXISTS ${EXT_NAME};\""
