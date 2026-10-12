# Apache serving static files only. The files live in the image, not a volume:
# they are code, not data, so a new version means a new image tag.
FROM httpd:2.4-alpine
COPY html/ /usr/local/apache2/htdocs/
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ >/dev/null || exit 1
