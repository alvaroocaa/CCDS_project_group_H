"""Core app: a tiny "page ratings" service.

Users (or the auto feeder) submit a rating (1-5) and a comment for a web page.
- Postgres stores every rating (persistent, critical data).
- Redis caches the leaderboard (volatile data, safe to lose).
- SMTP sends an alert mail when a page gets a 1-star rating.
- /metrics exposes Prometheus counters so Grafana can graph them.
"""
import json
import os
import smtplib
import socket
from email.message import EmailMessage

import psycopg
import redis
from flask import Flask, jsonify, request
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST


def read_secret(name, default=None):
    """Prefer a Docker secret file (production), fall back to an env var (local)."""
    path = os.environ.get(f"{name}_FILE")
    if path and os.path.exists(path):
        with open(path) as f:
            return f.read().strip()
    return os.environ.get(name, default)


DB_DSN = (
    f"host={os.environ.get('DB_HOST', 'db')} "
    f"dbname={os.environ.get('DB_NAME', 'ratings')} "
    f"user={os.environ.get('DB_USER', 'ratings')} "
    f"password={read_secret('DB_PASSWORD', 'ratings')} "
    "connect_timeout=2"  # fail fast instead of hanging when the db is unreachable
)
cache = redis.Redis(host=os.environ.get("REDIS_HOST", "redis"), port=6379, socket_timeout=1)
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "25"))
ALERT_TO = os.environ.get("ALERT_TO", "admin@example.test")

RATINGS = Counter("ratings_total", "Ratings received", ["stars"])
CACHE_HITS = Counter("leaderboard_cache_hits_total", "Leaderboard served from Redis")

app = Flask(__name__)


def db():
    return psycopg.connect(DB_DSN, autocommit=True)


def init_db():
    with db() as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS ratings (
                   id SERIAL PRIMARY KEY,
                   page TEXT NOT NULL,
                   stars INT NOT NULL CHECK (stars BETWEEN 1 AND 5),
                   comment TEXT,
                   created_at TIMESTAMPTZ DEFAULT now())"""
        )


def send_alert(page, comment):
    msg = EmailMessage()
    msg["Subject"] = f"1-star rating on {page}"
    msg["From"] = "core-app@example.test"
    msg["To"] = ALERT_TO
    msg.set_content(comment or "(no comment)")
    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=3) as s:
            s.send_message(msg)
    except OSError as e:  # mail is best effort, never break the request
        app.logger.warning("SMTP failed: %s", e)


@app.errorhandler(psycopg.Error)
def db_unavailable(e):
    # Any database failure becomes a clear 503 instead of an HTML 500 page
    app.logger.error("database error: %s", e)
    return jsonify(error="database unavailable"), 503


@app.get("/")
def index():
    # Which replica answered? Useful to see load balancing in swarm.
    return jsonify(service="core-app", replica=socket.gethostname())


@app.get("/health")
def health():
    # Liveness check only. If the db is down, restarting app replicas cannot fix it,
    # and failing here would make swarm restart ALL replicas in a loop (cascading
    # failure). So we report db/redis status but stay "healthy" while the process works.
    status = {"app": "ok"}
    try:
        with db() as conn:
            conn.execute("SELECT 1")
        status["db"] = "ok"
    except psycopg.Error:
        status["db"] = "down"
    try:
        cache.ping()
        status["redis"] = "ok"
    except redis.RedisError:
        status["redis"] = "down"
    return jsonify(status)


@app.post("/ratings")
def add_rating():
    data = request.get_json(force=True)
    page, stars, comment = data["page"], int(data["stars"]), data.get("comment", "")
    with db() as conn:
        conn.execute(
            "INSERT INTO ratings (page, stars, comment) VALUES (%s, %s, %s)",
            (page, stars, comment),
        )
    cache.delete("leaderboard")  # invalidate the cached leaderboard
    RATINGS.labels(stars=str(stars)).inc()
    if stars == 1:
        send_alert(page, comment)
    return jsonify(status="stored"), 201


@app.get("/leaderboard")
def leaderboard():
    try:
        cached = cache.get("leaderboard")
        if cached:
            CACHE_HITS.inc()
            return jsonify(json.loads(cached))
    except redis.RedisError:
        pass  # Redis down: degrade gracefully, go to the database
    with db() as conn:
        rows = conn.execute(
            "SELECT page, round(avg(stars), 2)::float, count(*) FROM ratings "
            "GROUP BY page ORDER BY 2 DESC LIMIT 10"
        ).fetchall()
    result = [{"page": p, "avg": a, "votes": n} for p, a, n in rows]
    try:
        cache.setex("leaderboard", 30, json.dumps(result))
    except redis.RedisError:
        pass
    return jsonify(result)


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


# The database may start after us: retry for ~30 s instead of crashing at once.
for attempt in range(15):
    try:
        init_db()
        break
    except psycopg.OperationalError:
        import time
        time.sleep(2)
