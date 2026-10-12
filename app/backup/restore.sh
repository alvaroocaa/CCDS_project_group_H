#!/bin/sh
# Disaster recovery: restore the ratings database from a dump.
# Usage (inside the backup container):
#   restore.sh                      -> restores the newest VALID dump
#   restore.sh ratings-XXXX.sql.gz  -> restores that specific dump
set -eu

DIR="${BACKUP_DIR:-/backups}"

if [ -n "${PGPASSWORD_FILE:-}" ] && [ -f "$PGPASSWORD_FILE" ]; then
  PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
fi
export PGPASSWORD

# A dump is valid only if it decompresses AND pg_dump wrote its end marker
is_valid() {
  gunzip -c "$1" 2>/dev/null | grep -q "PostgreSQL database dump complete"
}

if [ $# -ge 1 ]; then
  case "$1" in /*) FILE="$1" ;; *) FILE="$DIR/$1" ;; esac
  is_valid "$FILE" || { echo "ERROR: $FILE is not a complete dump, aborting" >&2; exit 1; }
else
  FILE=""
  for f in $(ls -1t "$DIR"/ratings-*.sql.gz 2>/dev/null); do
    if is_valid "$f"; then FILE="$f"; break; fi
    echo "skipping incomplete dump: $f" >&2
  done
  [ -n "$FILE" ] || { echo "ERROR: no valid dump found in $DIR" >&2; exit 1; }
fi

# Check we can log in BEFORE touching anything
psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -q -c "SELECT 1" >/dev/null

echo "Restoring $FILE into $PGDATABASE on $PGHOST"
# Only now, with a verified dump and a working login, wipe and reload
psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -q -c "SET client_min_messages TO warning; DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
gunzip -c "$FILE" | psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -q -v ON_ERROR_STOP=1 >/dev/null
echo "Restore finished"
