REG = 127.0.0.1:5050/ccds

# ---------- local (your Mac) ----------
local-up:
	docker network create proxy 2>/dev/null || true
	docker compose -f basic/compose.yml up -d --build
	docker compose -f app/compose.yml up -d --build

local-down:
	docker compose -f app/compose.yml down
	docker compose -f basic/compose.yml down

# ---------- swarm (run on node1) ----------
swarm-network:
	docker network create -d overlay --attachable proxy 2>/dev/null || true

registry: swarm-network
	docker stack deploy -c basic/production.yml basic

release:
	docker build -t $(REG)/nginx:1 basic/nginx
	docker push $(REG)/nginx:1

deploy: swarm-network
	docker stack deploy -c basic/production.yml basic