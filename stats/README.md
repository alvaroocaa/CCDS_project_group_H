# Stats stack: observability

Metrics for every container, every node and the app itself, shown in Grafana at
`https://grafana.<domain>/` (locally `http://grafana.localhost`).

| Service         | Image                              | Replicas      | Role                                               |
|-----------------|------------------------------------|---------------|----------------------------------------------------|
| `prometheus`    | `ccds/prometheus:1`                | 1             | Scrapes and stores metrics (time-series database)  |
| `grafana`       | `ccds/grafana:1`                   | 2             | Dashboards, datasources and plugin, all as code    |
| `grafana-db`    | `postgres:17`                      | 1             | Shared Grafana database (users, sessions)          |
| `cadvisor`      | `ghcr.io/google/cadvisor:v0.60.6`  | global (1/node) | CPU, memory and network of every container       |
| `node-exporter` | `prom/node-exporter:v1.9.1`        | global (1/node) | CPU, memory and disk of every machine            |

```
cadvisor (every node) ─┐
node-exporter (every node) ─┼──> prometheus ──> grafana x2 ──> nginx (grafana.<domain>)
app_core x3 /metrics ──┘                       │   └──> grafana-db
                          app_core /leaderboard ┘ (Infinity plugin)
```

## Observability as code

Nothing is configured by clicking in the UI. Everything is a file in this folder, baked into the images:

| File                                                | What it defines                                  |
|-----------------------------------------------------|--------------------------------------------------|
| `prometheus/prometheus.yml`                         | What to scrape in swarm (`tasks.*` DNS)          |
| `prometheus/prometheus.local.yml`                   | What to scrape locally (plain names)             |
| `grafana/provisioning/datasources/datasources.yml`  | Prometheus + App API datasources                 |
| `grafana/provisioning/dashboards/dashboards.yml`    | Loads every JSON dashboard into folder "CCDS"    |
| `grafana/dashboards/ccds-overview.json`             | The dashboard (UI edits are disabled)            |
| `grafana/Dockerfile`                                | Grafana version + plugin version                 |

To change a dashboard, edit it in Grafana, export the JSON, and replace the file in git.

## The "surprise" plugin: Infinity

[Infinity](https://grafana.com/grafana/plugins/yesoreyeram-infinity-datasource/) turns any HTTP
API (JSON, CSV, XML, GraphQL) into a Grafana datasource. We point it at the core app's
`/leaderboard`, so the dashboard shows **business data** (which pages are best rated, read live
from the app) next to the technical metrics. No exporter or extra code was needed in the app.
It is installed at build time (`grafana cli plugins install ... 4.0.0`), so replicas start
without internet. `allowedHosts` limits it to the app's URL.

## Dashboard "CCDS overview"

Core replicas up · ratings in the last hour · cache hits/min · swarm nodes reporting ·
ratings per minute by stars · **live leaderboard (Infinity)** · CPU and memory per container ·
CPU per node.

## Run locally

From the repo root (creates the shared `proxy` network, then starts basic, app and stats):

```bash
make local-up
```

| URL                              | What                                              |
|----------------------------------|---------------------------------------------------|
| http://grafana.localhost         | Grafana through nginx (admin / admin)             |
| http://127.0.0.1:3000            | Grafana directly                                  |
| http://127.0.0.1:9090/targets    | Prometheus targets                                |

Prometheus and Grafana join the `proxy` network, where the app's core answers as `core:8000`
and nginx reaches Grafana as `grafana:3000` (route: `basic/nginx/conf.d/grafana.conf`).
The `core` target and the leaderboard panel work only while `app/` is running.
Stop everything with `make local-down`.

## Deploy on the swarm

```bash
cd stats
openssl rand -base64 24 > secrets/grafana_admin_password.txt
openssl rand -base64 24 > secrets/grafana_db_password.txt
docker compose -f production.yml build
docker compose -f production.yml push
docker stack deploy -c production.yml stats
```

Needs from the basic stack: the attachable overlay network `proxy`, the registry, and an nginx
route for `grafana.<domain>`. In the swarm the service is called `stats_grafana`, so the
production route must point at `stats_grafana:3000`.
The stack name **must be `stats`**, because Prometheus uses the names `tasks.stats_cadvisor`,
`tasks.stats_node-exporter`, and so on.
Log in with user `admin` and the password in `secrets/grafana_admin_password.txt`.

## Data and backups

| What                        | Where                                | Backed up? | If it is lost                                     |
|-----------------------------|--------------------------------------|------------|---------------------------------------------------|
| Dashboards, datasources     | in the Grafana image (git)           | No         | Redeploy: they are code                           |
| Metrics history             | `prometheus_data`, local volume on the manager | No | Graphs restart from zero; scraping refills them |
| Grafana users and sessions  | `grafana_db_data`, local volume on the manager | No | Users log in again; admin comes from the secret |
| Passwords                   | Docker secrets                       | No         | Create new secret files                           |

Nothing here is critical data, which is the point of observability as code: the valuable part
(the dashboards) lives in git. Metrics history is "nice to have". Backing it up would mean dumping
a database that refills itself.

## Design notes

- **`tasks.<service>` in Prometheus.** A plain service name resolves to one virtual IP that
  load-balances across replicas, so each scrape would hit a random replica. `tasks.app_core` returns
  every replica's IP, so Prometheus scrapes each one (verified: 2 core replicas = 2 targets).
- **cAdvisor and node-exporter run in `mode: global`.** One copy per node, so each machine is measured where it
  runs. A node that joins the swarm gets them automatically.
- **Grafana can scale because of `grafana-db`.** With the default SQLite file, each replica has its own
  sessions, and the load balancer logs you out. With a shared Postgres, a login works on every replica.
  When two replicas start against an empty database, one waits for the other's migration lock. In our test,
  the loser exited, Swarm restarted it a few seconds later, and both became healthy.
- **Prometheus and grafana-db stay at 1 replica** (DBMS exception). They are pinned to
  `node.role == manager`, so they always find their local volume. Prometheus doesn't support
  NFS for its data.
- **`monitoring` is an `internal` network.** Nothing in this stack needs the internet.
- **Memory limit for Grafana: 512 MB.** We measured Grafana 13 idling at about 430 MB with cAdvisor. Our first
  guess (256 MB) would have made Swarm kill it in a loop.
- **cAdvisor mounts the Docker and containerd sockets.** Since Docker 29 stores images with the
  containerd snapshotter, older cAdvisor versions (0.52) cannot see containers at all. 0.60
  needs `/run/containerd/containerd.sock`.

## Tested (13 Oct 2026)

| Test (local compose and one-node swarm)          | Result                                                  |
|--------------------------------------------------|---------------------------------------------------------|
| Prometheus targets                               | prometheus, cadvisor, node, core: all `up`              |
| Swarm: `tasks.app_core`                          | 2 core targets, one per replica                         |
| Container metrics                                | 12 containers locally, 20 on the swarm                  |
| Dashboard and datasources provisioned            | folder CCDS, "CCDS overview", 2 datasources             |
| Infinity → `/leaderboard`                        | returns the live leaderboard table                      |
| Login with the secret password                   | `200`; default `admin` password rejected with `401`     |
| Session on 2 replicas                            | 10 of 10 requests with the same cookie accepted         |
