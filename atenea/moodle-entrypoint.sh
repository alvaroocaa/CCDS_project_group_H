#!/bin/sh
# Installs Moodle automatically on the first start, then just runs Apache.
set -e
ROOT=/var/www/html
DATA=/var/www/moodledata
SAVED=$DATA/config.php.saved

find_cfg() { ls $ROOT/config.php 2>/dev/null; }
CLI=$(ls $ROOT/admin/cli/install.php $ROOT/public/admin/cli/install.php 2>/dev/null | head -1)

# Container recreated but Moodle already installed: restore its config
if [ -z "$(find_cfg)" ] && [ -f "$SAVED" ]; then
  cp "$SAVED" "$ROOT/config.php"
fi

if [ -z "$(find_cfg)" ]; then
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
  cp "$(find_cfg)" "$SAVED"
  chown -R www-data:www-data "$DATA"
  echo "Moodle: installation complete"
fi

chmod 644 "$ROOT/config.php" 2>/dev/null || true

exec apache2-foreground