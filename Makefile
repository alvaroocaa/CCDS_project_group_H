REG = 127.0.0.1:5050/ccds
HTTP_PORT ?= 80
export HTTP_PORT

# ---------- local ----------
secrets:
	@for f in $$(find . -name "*.example" -not -path "./.git/*"); do \
	  [ -f "$${f%.example}" ] || { cp "$$f" "$${f%.example}"; echo "created $${f%.example}"; }; \
	done

local-up: secrets
	docker network create proxy 2>/dev/null || true
	docker compose -f basic/compose.yml up -d --build
	docker compose -f app/compose.yml up -d --build
	docker compose -f stats/compose.yml up -d --build
	docker compose -f atenea/compose.yml up -d --build
	@echo ""
	@echo "Starting up. Wait ~2 minutes (Moodle ~5 on the first start), then open:"
	@echo "  http://app.localhost:$(HTTP_PORT)          core app"
	@echo "  http://app.localhost:$(HTTP_PORT)/static/  static page"
	@echo "  http://grafana.localhost:$(HTTP_PORT)      Grafana"
	@echo "  http://moodle.localhost:$(HTTP_PORT)       Moodle"
	@echo "Check progress with: make status"
	@echo "  http://mail.localhost:$(HTTP_PORT)         Mailbox (alerts for 1-star ratings)"

status:
	@docker ps --format 'table {{.Names}}\t{{.Status}}'

local-down:
	docker compose -f atenea/compose.yml down
	docker compose -f stats/compose.yml down
	docker compose -f app/compose.yml down
	docker compose -f basic/compose.yml down

local-clean:
	docker compose -f atenea/compose.yml down -v
	docker compose -f stats/compose.yml down -v
	docker compose -f app/compose.yml down -v
	docker compose -f basic/compose.yml down -v

# ---------- swarm (run on node1) ----------
export REGISTRY = 127.0.0.1:5050
export DOMAIN = ccds-group-h.duckdns.org

swarm-network:
	docker network create -d overlay --attachable proxy 2>/dev/null || true

registry: swarm-network
	docker stack deploy -c basic/production.yml basic

release:
	docker build -t $(REG)/nginx:1 basic/nginx
	docker push $(REG)/nginx:1
	docker compose -f app/production.yml build
	docker compose -f app/production.yml push --ignore-push-failures
	docker compose -f stats/production.yml build
	docker compose -f stats/production.yml push --ignore-push-failures
	docker compose -f atenea/production.yml build
	docker compose -f atenea/production.yml push --ignore-push-failures

deploy: swarm-network
	docker stack deploy -c basic/production.yml basic
	docker stack deploy -c app/production.yml app
	docker stack deploy -c stats/production.yml stats
	docker stack deploy -c atenea/production.yml atenea

.PHONY: secrets local-up status local-down local-clean swarm-network registry release deploy