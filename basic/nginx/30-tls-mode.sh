#!/bin/sh
# Picks HTTP or HTTPS mode depending on whether the certificate exists.
CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem

write_conf() {
  if [ -f "$CERT" ]; then
    cat > /etc/nginx/snippets/listen.conf <<EOF
listen 443 ssl;
http2 on;
ssl_certificate $CERT;
ssl_certificate_key $KEY;
EOF
    cat > /etc/nginx/conf.d/00-redirect.conf <<'EOF'
server {
    listen 80 default_server;
    include /etc/nginx/snippets/acme.conf;
    location / { return 301 https://$host$request_uri; }
}
EOF
    echo https
  else
    echo "listen 80;" > /etc/nginx/snippets/listen.conf
    rm -f /etc/nginx/conf.d/00-redirect.conf
    echo http
  fi
}

MODE=$(write_conf)
echo "tls-mode: $MODE"

# Every minute: switch mode when the cert appears; every 12h: reload to pick up renewals
(
  i=0
  while sleep 60; do
    NEW=$(write_conf)
    i=$((i+1))
    if [ "$NEW" != "$MODE" ] || [ $((i % 720)) -eq 0 ]; then
      MODE=$NEW
      echo "tls-mode: $MODE (reloading)"
      nginx -s reload
    fi
  done
) &