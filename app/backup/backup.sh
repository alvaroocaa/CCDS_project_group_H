#!/bin/sh
# Dump backup: every BACKUP_INTERVAL seconds, dump the ratings database to a
# compressed SQL file and keep only the newest BACKUP_KEEP copies (some history).
set -eu

INTERVAL="${BACKUP_INTERVAL:-3600}"
KEEP="${BACKUP_KEEP:-24}"
DIR="${BACKUP_DIR:-/backups}"

# pg_dump reads the password from PGPASSWORD; prefer a secret file if given
if [ -n "${PGPASSWORD_FILE:-}" ] && [ -f "$PGPASSWORD_FILE" ]; then
  PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
fi
export PGPASSWORD

while true; do
  FILE="$DIR/ratings-$(date +%Y%m%d-%H%M%S).sql.gz"
  # pg_dump compresses by itself, so its OWN exit code decides success.
  # (With "pg_dump | gzip" the shell only checks gzip, and a failed dump
  #  becomes an empty "backup" that looks valid. We hit exactly that bug.)
  if pg_dump -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" --compress=gzip:6 -f "$FILE.tmp" \
     && gunzip -c "$FILE.tmp" | grep -q "PostgreSQL database dump complete"; then
    mv "$FILE.tmp" "$FILE"
    echo "$(date -Iseconds) backup ok: $FILE ($(du -h "$FILE" | cut -f1))"
  else
    rm -f "$FILE.tmp"
    echo "$(date -Iseconds) backup FAILED, previous backups kept" >&2
  fi
  # Rotation: delete everything except the newest $KEEP dumps
  ls -1t "$DIR"/ratings-*.sql.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f
  sleep "$INTERVAL"
done
