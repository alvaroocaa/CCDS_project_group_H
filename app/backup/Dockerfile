# Reuse the official postgres image only for its pg_dump/psql tools:
# same major version as the db service, so dumps are always compatible.
FROM postgres:17

COPY backup.sh restore.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh \
 && mkdir -p /backups && chown postgres:postgres /backups

# A new named volume copies this ownership on first mount, so no root needed
USER postgres
VOLUME /backups

# Replace the image's entrypoint: we do NOT want to start a second Postgres server
ENTRYPOINT ["/usr/local/bin/backup.sh"]
