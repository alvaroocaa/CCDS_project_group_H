FROM python:3.12-slim

# Dependencies first: Docker caches this layer, so code edits don't reinstall packages
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Do not run as root inside the container
RUN useradd --create-home appuser
USER appuser

EXPOSE 8000

# Swarm/compose use this to detect a broken replica and replace it (autohealing)
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# One foreground process, logs to stdout. One gunicorn worker per container:
# we scale with more replicas, not more workers.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", \
     "--access-logfile", "-", "app:app"]
