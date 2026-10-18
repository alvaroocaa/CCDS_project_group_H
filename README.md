# Cloud Computing and Distributed Systems Short Project – Group H

By:
* Alvaro Castillejo
* Berk Gonenc
* Sepehr Ashtari
* Abdelkrim Alahyane

---

## Contents

1. [Overview](#overview)
2. [Run locally](#run-locally)
3. [Architecture](#architecture)
4. [Stacks](#stacks)
    - [Basic – Front end and infrastructure](#basic--front-end-and-infrastructure)
    - [App – Rating application](#app--rating-application)
    - [Stats – Monitoring](#stats--monitoring)
    - [Atenea – Moodle](#atenea--moodle)
5. [Production deployment (Docker Swarm on Azure)](#production-deployment-docker-swarm-on-azure)
6. [Data management and backups](#data-management-and-backups)
7. [Scalability](#scalability)
8. [Security](#security)
9. [Evidences](#evidences)
10. [Requirements checklist](#requirements-checklist)
11. [Repository layout](#repository-layout)

---

## Overview

The project is divided into four stacks, all reached through one nginx front end:


| Stack | Services | Purpose |
|---|---|---|
| `basic` | nginx, certbot (Let's Encrypt), registry, NFS | Shared services for the whole infrastructure |
| `app` | core (Python), Postgres, Redis, Apache static, feeder bot, DB backup, SMTP relay (Mailpit) | "Page ratings" application |
| `stats` | Prometheus, cAdvisor, node-exporter, Grafana (+ Infinity plugin) | Monitoring of every container, node and the app |
| `atenea` | Moodle 5.3, MariaDB, Moodle cron | Learning Management System |

Each stack has two compose files, as required:

- `compose.yml` – **local** environment: one machine, no TLS, no shared volumes, plain local passwords.
- `production.yml` – **production**: Docker Swarm, replicas, Docker secrets, overlay networks, NFS.

---

## Run locally

**Requirements:** Docker (running) and `make`. To start the environment locally execute the following command:

```bash
make local-up
```

This make commands starts the following services:

- Missing secret files are created automatically from the `.example` files.
- Wait around 2 minutes. **Moodle installs itself on the first start (up to 5 minutes).**
- Check progress with `make status`.

The different stacks are reachable from the following URLs:

| URL | What | Login (local only) |
|---|---|---|
| http://app.localhost | Core app API (JSON, shows which replica answered) | n/a |
| http://app.localhost/static/ | Rate a page and see the live leaderboard | n/a |
| http://grafana.localhost | Grafana, dashboard "CCDS overview" | `admin` / `admin` |
| http://moodle.localhost | Moodle LMS | `admin` / `Atenea-Admin1` |
| http://mail.localhost | Mailbox: an alert arrives for every 1-star rating | n/a |

Only nginx publishes a port (80); every other service is reachable only through it. The `make` commands in the project are the following:

```bash
make status        # check container status
make local-down    # stop containers but maintain data
make local-clean   # stop containers and delete all data (next start is a fresh install)
```

---

## Architecture

![Architecture](architecture.png)

**Request path:** browser → nginx (`<service>.<domain>`) → service on the shared `proxy` network.

**Networks**

| Network | Type | Who is on it | Why |
|---|---|---|---|
| `proxy` | external, overlay (attachable) in swarm | nginx + every service nginx routes to | Single shared contract between stacks |
| `app_backend` | overlay, `internal` | core, Postgres, Redis, feeder, backup, stmp | Database and cache unreachable from nginx and from the internet |
| `atenea_backend` | overlay, `internal` | Moodle, MariaDB, cron | Same for the LMS |
| `stats_monitoring` | overlay, `internal` | Prometheus, Grafana, grafana-db, exporters | Monitoring internals isolated |

**Routing (nginx)** – one template per subdomain in `basic/nginx/templates/`, with `${DOMAIN}`
filled in at start (`localhost` locally, `ccds-group-h.duckdns.org` in production):

| Host | Upstream |
|---|---|
| `app.<domain>/` and `/app/` | `core:8000` |
| `app.<domain>/static/` | `static:80` |
| `grafana.<domain>` | `grafana:3000` (incl. websockets for Grafana Live) |
| `moodle.<domain>` | `moodle:80` |
| `registry.<domain>/v2/` | `registry:5000` (basic auth) |
| `mail.<domain>` | `smtp:8025` (Mailpit web mailbox, local demo only) |

nginx resolves upstreams per request through Docker's DNS (`resolver 127.0.0.11`), so it starts even
when the other stacks are not deployed yet (it answers 502 until they are).

---
## Stacks

## Basic – Front end and infrastructure

Files: `basic/`, `scripts/`, `Makefile`.

- **Nginx:** Web server with HTTPS support. Uses 2 replicas in production.
- **Let's Encrypt:** Automatically issues and renews certificates for the application, Grafana, Moodle and registry.
- **Registry:** Stores Docker images on NFS. Internal access uses port 5050; external access uses HTTPS and password protection.
- **NFS:** Shared storage hosted on node1 and mounted on all nodes. Stores certificates, Docker images and application data.

## App – Rating application

Files: `app/`

The application lets users rate web pages from 1 to 5 stars and displays a live leaderboard.

| Service | Replicas | Purpose |
|---|---:|---|
| Core | 3 | Handles ratings, leaderboard and alerts |
| Static | 2 | Serves the website |
| Auto-feeder | 1 | Automatically submits test ratings |
| PostgreSQL | 1 | Stores ratings |
| Redis | 1 | Caches the leaderboard |
| Backup | 1 | Backs up the database hourly |
| SMTP (Mailpit) | 1 | Relays alert mails; locally keeps them in a web mailbox |

- **Rating form:** the static page has a form that posts to the core API (`/app/ratings`); the
  leaderboard refreshes every 10 s.
- **SMTP:** a 1-star rating makes the core app send an alert mail to the `smtp` service (Mailpit).
  Locally Mailpit keeps the mails in a web mailbox (http://mail.localhost); in production it can forward
  them to a real provider with its `MP_SMTP_RELAY_*` settings.

## Stats – Monitoring

Files: `stats/`

| Service | Replicas | Purpose |
|---|---:|---|
| Prometheus | 1 | Collects monitoring data |
| cAdvisor | 1 per node | Monitors containers |
| Node Exporter | 1 per node | Monitors servers |
| Grafana | 2 | Displays dashboards |
| Grafana DB | 1 | Stores Grafana data |

- **Configuration as code:** Dashboards and data sources are configured through files in Git.
- **Infinity plugin:** Displays application data, including the leaderboard, in Grafana.

## Atenea – Moodle

Files: `atenea/`

| Service | Replicas | Purpose |
|---|---:|---|
| Moodle | 2 | Learning management system |
| MariaDB | 1 | Stores Moodle data |
| Cron | 1 | Runs scheduled Moodle tasks every minute |

- **Automatic setup:** Moodle installs itself on first startup and restores its configuration when restarted.
- **Multiple replicas:** Both Moodle instances share storage and configuration.
- **HTTPS:** Nginx handles HTTPS connections.
- **Secrets:** Production passwords are stored securely using Docker secrets.

---

## Production deployment (Docker Swarm on Azure)

### Cluster

| | |
|---|---|
| Nodes | 3 × Standard B2als_v2 (2 vCPU, 4 GB), Ubuntu 24.04, one virtual network |
| node1 `172.16.0.4` | swarm manager, NFS server, the only node with HTTP/HTTPS open |
| node2 `172.16.1.4` | worker, labelled `db=true` (Postgres and MariaDB run here) |
| node3 `172.16.2.4` | worker |
| Domain | `ccds-group-h.duckdns.org` (DuckDNS, `*.` subdomains → node1) |

Node setup and swarm creation: `scripts/swarm-up.sh`. NFS server: `scripts/nfs-server.sh`.

### Deploy

On node1, from the repository:

```bash
# Execute only the first time before the images can be pushed
make registry
# Build all images and push them to the registry, then deploy the 4 stacks
make release
make deploy
```

Before the first deploy: real passwords in `app/secrets/`, `stats/secrets/`, `atenea/secrets/` and
`basic/registry/htpasswd` (never committed), NFS folders created, node2 labelled `db=true`.

Images are always built on node1 (x86).

---

## Data management and backups

The question for every piece of data: *is it data at all, and is it critical?*

| Data | Kind | Local | Production | Backed up | If lost |
|---|---|---|---|---|---|
| Ratings (Postgres) | Critical | volume `app_db_data` | local volume on node2 (`db=true`) | **Yes**, hourly `pg_dump` to NFS, 48 kept | Restore last dump (`restore.sh`) |
| Moodle database (MariaDB) | Critical | volume `atenea_db_data` | local volume on node2 | Manual `mariadb-dump` (see below); not automated | Restore the last dump |
| Moodle files (moodledata) | Critical | volume `atenea_moodledata` | NFS `/srv/nfs/atenea/moodledata` | Manual `tar` of the NFS folder | Restore the archive |
| Leaderboard cache (Redis) | Volatile | memory only | memory only | No | Rebuilt from Postgres |
| Metrics (Prometheus) | Nice to have | volume | local volume on the manager | No | Graphs restart, scraping refills |
| Grafana users/sessions | Low | SQLite volume | Postgres `grafana-db` | No | Users log in again |
| Dashboards, nginx config, code | Code | in images (git) | in images (git) | git | Rebuild and redeploy |
| TLS certificates | Regenerable | – | NFS | No | certbot issues new ones |
| Registry images | Regenerable | – | NFS | No | `make release` |
| Passwords | Secrets | `.txt` from `.example` | Docker secrets | No | Create new secret files |

**Why databases are not on NFS:** file locking on network filesystems can corrupt databases and makes
them slow. Databases stay on a local volume on a labelled node; their 

**Moodle backup (manual).** Only the app database has an automatic backup job, as required by the
statement. Moodle is backed up by hand; automating it would reuse the same pattern as `app/backup`
(a cron container dumping to NFS).

**dumps** go to NFS so they survive
the loss of that node.

---

## Scalability

The statement requires every service to be scalable, except cron jobs and DBMSs.

| Service | Replicas | Scales? |
|---|---|---|
| nginx | 2 | Yes |
| registry | 1 | Yes (storage on NFS) |
| certbot | 1 | No – cron job |
| core | 3 | Yes (stateless) |
| static | 2 | Yes |
| auto | 1 | Yes (more replicas = more traffic) |
| redis | 1 | One shared cache by design |
| postgres, mariadb, grafana-db | 1 | No – DBMS |
| backup, moodle cron | 1 | No – cron jobs |
| grafana | 2 | Yes (shared Postgres) |
| prometheus | 1 | No – time-series DBMS |
| cadvisor, node-exporter | global | One per node |
| moodle | 2 | Yes (shared moodledata, install lock) |
| smtp (Mailpit) | 1 | One mailbox by design (messages stored in the container) |

```bash
docker service scale app_core=5
```

---

## Security

- **Only 22, 80 and 443 are open from the internet**; NFS (2049), registry (5050) and swarm ports are
  reachable only inside the Azure virtual network (checked from outside: all closed).
- **HTTPS everywhere** in production, HTTP redirected to HTTPS.
- **Docker secrets** for every production password; only `.example` files are in git.
- **Internal networks** for databases and caches; nginx cannot reach them.
- **Registry** behind basic auth; **Grafana** admin password from a secret; **Infinity** limited to the app URL.
- Containers run as non-root users where the image allows it (core, feeder, backup).

---

## Evidences

The docker swarm has been correctly deployed on Azure with the 3 nodes and all 18 services deployed as visible in the image below:

![Evidence](deployment_azure.png)

The screenshot has been taken from the node1 in the Docker Swarm where the deployment is performed.

---

## Requirements checklist

| Requirement (statement) | Where |
|---|---|
| compose.yml files | `basic/`, `app/`, `stats/`, `atenea/` |
| production.yml files | same folders |
| Dockerfiles + build files | `basic/nginx/`, `app/core/`, `app/auto/`, `app/static/`, `app/backup/`, `stats/grafana/`, `stats/prometheus/`, `atenea/` |
| Documentation of deployment, data and backups | this README, `app_stack_report.pdf`, `stats/README.md` |
| Swarm with ≥ 3 nodes | [Production deployment](#production-deployment-docker-swarm-on-azure) |
| Shared disk between nodes | NFS ([basic](#basic--front-end-and-infrastructure)) |
| Front end proxying to every service | nginx templates |
| Let's Encrypt TLS | certbot service |
| Registry | `registry:2` + nginx auth |
| Core app, db, dump backup, static server, cache, SMTP, feeder | `app/` |
| Grafana as code + plugin | `stats/` (Infinity) |
| Moodle + database | `atenea/` |
| No extra steps besides build and deploy | `make local-up` / `make release && make deploy` |
| All services scalable except cron jobs and DBMS | [Scalability](#scalability) |

---

## Repository layout

```
basic/     nginx (Dockerfile, templates/, snippets/, 30-tls-mode.sh), registry/   compose.yml, production.yml
app/       core/, auto/, static/, backup/, secrets/*.example                       compose.yml, production.yml
stats/     grafana/ (provisioning/, dashboards/), prometheus/, secrets/*.example    compose.yml, production.yml
atenea/    Dockerfile, moodle-entrypoint.sh, secrets/*.example                      compose.yml, production.yml
scripts/   swarm-up.sh, nfs-server.sh
Makefile   local-up, local-down, local-clean, status | registry, release, deploy
```