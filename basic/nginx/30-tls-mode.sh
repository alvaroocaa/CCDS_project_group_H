#!/bin/sh
# Picks HTTP or HTTPS mode, and reloads nginx whenever the certificate changes.
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

# mode + certificate timestamp: changes on issue, renewal or replacement
state() { echo "$(write_conf):$(stat -L -c %Y "$CERT" 2>/dev/null)"; }

STATE=$(state)
echo "tls-mode: $STATE"

(
  while sleep 60; do
    NEW=$(state)
    if [ "$NEW" != "$STATE" ]; then
      STATE=$NEW
      echo "tls-mode: $STATE (reloading)"
      nginx -s reload
    fi
  done
) &