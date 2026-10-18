#!/bin/sh
# Installs Moodle automatically on the first start, then runs Apache.
# Same behaviour locally (one container) and on the swarm (replicas sharing moodledata on NFS).
set -e
ROOT=/var/www/html
DATA=/var/www/moodledata
SAVED=$DATA/config.php.saved
LOCK=$DATA/.installing

# Docker secrets: MOODLE_X_FILE=/run/secrets/... -> MOODLE_X=<file content>
for v in MOODLE_DB_PASSWORD MOODLE_ADMIN_PASSWORD; do
  f=$(eval echo "\${${v}_FILE:-}")
  if [ -n "$f" ] && [ -f "$f" ]; then export "$v=$(cat "$f")"; fi
done

CLI=$(ls $ROOT/admin/cli/install.php $ROOT/public/admin/cli/install.php 2>/dev/null | head -1)

# Container recreated but Moodle already installed: restore its config
if [ ! -f "$ROOT/config.php" ] && [ -f "$SAVED" ]; then
  cp "$SAVED" "$ROOT/config.php"
fi

if [ ! -f "$ROOT/config.php" ]; then
  if mkdir "$LOCK" 2>/dev/null; then          # only one replica installs
    echo "Moodle: waiting for the database..."
    until php -r 'exit(@mysqli_connect(getenv("MOODLE_DB_HOST"),getenv("MOODLE_DB_USER"),getenv("MOODLE_DB_PASSWORD"),getenv("MOODLE_DB_NAME"))?0:1);'; do
      sleep 3
    done
    echo "Moodle: first start, installing (takes a few minutes)..."
    php "$CLI" --non-interactive --agree-license --lang=en \
      --wwwroot="$MOODLE_WWWROOT" --dataroot="$DATA" \
      --dbtype=mariadb --dbhost="$MOODLE_DB_HOST" --dbname="$MOODLE_DB_NAME" \
      --dbuser="$MOODLE_DB_USER" --dbpass="$MOODLE_DB_PASSWORD" \
      --fullname="CCDS Atenea" --shortname="atenea" \
      --adminuser=admin --adminpass="$MOODLE_ADMIN_PASSWORD" --adminemail=admin@example.com
    cp "$ROOT/config.php" "$SAVED"
    chown -R www-data:www-data "$DATA"
    rmdir "$LOCK"
    echo "Moodle: installation complete"
  else
    echo "Moodle: another replica is installing, waiting..."
    until [ -f "$SAVED" ]; do sleep 5; done
    cp "$SAVED" "$ROOT/config.php"
  fi
fi

# Behind nginx with HTTPS (production): Moodle must generate https:// links
if [ "${MOODLE_SSLPROXY:-0}" = "1" ] && ! grep -q sslproxy "$ROOT/config.php"; then
  sed -i '/require_once/i $CFG->sslproxy = true;' "$ROOT/config.php"
fi

chmod 644 "$ROOT/config.php"

exec apache2-foreground