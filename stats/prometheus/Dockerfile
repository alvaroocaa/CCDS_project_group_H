# Prometheus with its scrape configuration baked in: the config is code, it is
# versioned with the image, and no node needs a copy of the file on its disk.
FROM prom/prometheus:v3.4.1
COPY prometheus.yml prometheus.local.yml /etc/prometheus/
