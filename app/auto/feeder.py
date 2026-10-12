"""Auto feeder: a bot that keeps fake ratings flowing into the core app.

It simulates visitors rating web pages, so Postgres, Redis and Grafana
always have fresh data to show. Standard library only: no pip install needed.
"""
import json
import os
import random
import time
import urllib.request

CORE_URL = os.environ.get("CORE_URL", "http://core:8000")
INTERVAL = float(os.environ.get("INTERVAL_SECONDS", "5"))

PAGES = ["upc.edu", "atenea.upc.edu", "docs.docker.com", "github.com", "wikipedia.org"]
COMMENTS = {
    1: ["Broken links everywhere", "Too slow to load"],
    2: ["Hard to navigate", "Outdated content"],
    3: ["It's ok", "Average experience"],
    4: ["Useful page", "Clear and fast"],
    5: ["Excellent!", "Exactly what I needed"],
}


def post_rating():
    stars = random.choices([1, 2, 3, 4, 5], weights=[1, 2, 3, 5, 4])[0]
    body = json.dumps({
        "page": random.choice(PAGES),
        "stars": stars,
        "comment": random.choice(COMMENTS[stars]),
    }).encode()
    req = urllib.request.Request(
        f"{CORE_URL}/ratings", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        print(f"posted {stars} stars -> HTTP {resp.status}", flush=True)


while True:
    try:
        post_rating()
    except OSError as e:  # core not up yet or restarting: just try again later
        print(f"core unreachable: {e}", flush=True)
    time.sleep(INTERVAL)
