# Grafana with everything defined as code (observability as code):
# datasources, dashboards and plugins are files in this image, not clicks in the UI.
# Every replica starts identical, and a lost Grafana is rebuilt from git.
FROM grafana/grafana:13.2.2

# The "surprise" plugin: Infinity, a datasource that reads any JSON/CSV/XML HTTP
# API. We point it at the app's /leaderboard, so Grafana shows business data
# (best rated pages), not only CPU graphs. Installed at build time: replicas
# start offline and fast. Kept outside /var/lib/grafana so a volume can't hide it.
ENV GF_PATHS_PLUGINS=/opt/grafana-plugins
USER root
RUN mkdir -p "$GF_PATHS_PLUGINS" \
 && grafana cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install yesoreyeram-infinity-datasource 4.0.0 \
 && chown -R grafana "$GF_PATHS_PLUGINS"
USER grafana

COPY provisioning/ /etc/grafana/provisioning/
COPY dashboards/ /etc/grafana/dashboards/

ENV GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_ANALYTICS_CHECK_FOR_UPDATES=false

HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1
