FROM nginx:1.27-alpine
RUN rm -f /etc/nginx/conf.d/default.conf \
 && mkdir -p /var/www/certbot /etc/nginx/snippets
COPY snippets/acme.conf /etc/nginx/snippets/acme.conf
COPY 30-tls-mode.sh /docker-entrypoint.d/30-tls-mode.sh
RUN chmod +x /docker-entrypoint.d/30-tls-mode.sh
COPY templates/ /etc/nginx/templates/