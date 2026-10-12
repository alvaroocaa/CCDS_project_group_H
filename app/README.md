# App stack: page ratings service

A small microservices app: visitors (or a bot) rate web pages from 1 to 5 stars,
and the app keeps a live leaderboard. It runs as six containers on Docker Swarm.

| Service  | Image                     | Replicas | Networks       | Role                                              |
|----------|---------------------------|----------|----------------|---------------------------------------------------|
| `core`   | `ccds/core-app:3`         | 3        | proxy, backend | Flask API: ratings, leaderboard, alerts, metrics  |
| `static` | `ccds/static:1`           | 2        | proxy          | Apache serving the HTML page                      |
| `auto`   | `ccds/auto-feeder:1`      | 1        | backend        | Bot posting a fake rating every 5 s               |
| `db`     | `postgres:17`             | 1        | backend        | Stores every rating (critical data)               |
| `redis`  | `redis:7-alpine`          | 1        | backend        | Caches the leaderboard for 30 s (volatile data)   |
| `backup` | `ccds/db-backup:2`        | 1        | backend        | Hourly `pg_dump` to NFS, keeps the last 48 dumps  |

## Folder layout

```
app/
├── compose.yml              # local: one machine, published ports, plain passwords
├── production.yml           # swarm: replicas, secrets, overlay networks, NFS backups
├── nginx-app.conf           # routes for the basic stack's nginx (part A)
├── secrets/
│   └── db_password.txt.example   # copy to db_password.txt (git-ignored)
├── core/                    # Flask app: app.py, requirements.txt, Dockerfile
├── auto/                    # rating bot: feeder.py, Dockerfile
├── static/                  # html/ + Dockerfile (Apache)
└── backup/                  # backup.sh, restore.sh, Dockerfile
```

## Core app API

| Method | Path           | What it does                                                   |
|--------|----------------|----------------------------------------------------------------|
| GET    | `/`            | Returns the hostname of the replica that answered             |
| GET    | `/health`      | Liveness check; also reports db and redis status              |
| POST   | `/ratings`     | Body `{"page": "...", "stars": 1-5, "comment": "..."}`        |
| GET    | `/leaderboard` | Top 10 pages by average rating (Redis cache, 30 s)            |
| GET    | `/metrics`     | Prometheus counters: `ratings_total{stars}`, `leaderboard_cache_hits_total` |

A 1-star rating sends an email alert through the `smtp` service.

## Run locally

```bash
cd app
docker compose up -d --build
curl localhost:8000/leaderboard
open http://localhost:8080
```

Stop with `docker compose down` (keeps data) or `docker compose down -v` (wipes data).

> zsh users: don't paste `# comments` on the same line as a command, or run
> `setopt interactivecomments` first.

## Deploy on the swarm

**Prerequisites**:

1. An attachable overlay network called `proxy`:
   `docker network create --driver overlay --attachable proxy`
2. The NFS share mounted at `/mnt/nfs` on every node, with a folder
   `app-backups/` writable by uid 999 (the postgres user).
3. One node labelled for the database:
   `docker node update --label-add db=true <node-name>`
4. A registry reachable by all nodes (default `localhost:5000`; override with `REGISTRY`).

**Deploy:**

```bash
cd app
cp secrets/db_password.txt.example secrets/db_password.txt
openssl rand -base64 24 > secrets/db_password.txt
docker compose -f production.yml build
docker compose -f production.yml push
docker stack deploy -c production.yml app
docker stack services app
```

Use another registry with `REGISTRY=my.registry:5000 docker compose -f production.yml build`
(same variable for `push` and `stack deploy`). Use a different NFS mount point with `NFS_ROOT=/path`.

## Integration with the other stacks

| Who needs it   | Address                    | Notes                                                    |
|----------------|----------------------------|----------------------------------------------------------|
| nginx (part A) | `app_core:8000`            | Route `/app/`; see `nginx-app.conf`                      |
| nginx (part A) | `app_static:80`            | Route `/static/`                                         |
| Grafana / Prometheus (part D) | `tasks.app_core:8000/metrics` | Use `tasks.` DNS to scrape every replica, not one at random |
| core app → SMTP (part D) | `smtp:25`        | Plain SMTP, no auth. Set `SMTP_HOST` if the service has another name |

`/app/metrics` is blocked in `nginx-app.conf`, so metrics stay internal.

## Scaling, updates and rollback

```bash
docker service scale app_core=5
docker service update --image localhost:5000/ccds/core-app:3 app_core
docker service rollback app_core
docker service ps app_core
```

Rolling updates replace one replica at a time, start the new one before stopping
the old one, and roll back automatically if the new version is unhealthy within 30 s.
A `start-first` update needs a free slot per node: on a single-node test swarm, run
`docker service update --replicas-max-per-node 0 app_core` first.

## Backups and disaster recovery

- Dumps land in `/mnt/nfs/app-backups/ratings-YYYYMMDD-HHMMSS.sql.gz` every hour.
- RPO (maximum data loss) = backup interval = 1 hour.
- The database itself stays on a local volume on the `db=true` node (no database on NFS).

**Restore the newest dump:**

```bash
docker exec -it $(docker ps -q -f name=app_backup) restore.sh
```

**Restore a specific dump:**

```bash
docker exec -it $(docker ps -q -f name=app_backup) restore.sh ratings-20261011-145752.sql.gz
```

**If the database node dies:** label another node `db=true`, run
`docker stack deploy -c production.yml app` again (Postgres starts there with an
empty volume), then run the restore command above.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `app_core` shows `2/3` on a 1-node swarm | `max_replicas_per_node: 2` | Expected; on 3 nodes it reaches 3/3 |
| Update stuck: "no suitable node" | `start-first` needs a free slot | See Scaling section |
| App can't log in to db after switching to swarm | Old volume created with the old password | `docker compose down -v`, or remove the `app_db_data` volume |
| `/health` shows `"db": "down"` | Postgres unreachable | `docker service ps app_db`; the app keeps running on purpose |
