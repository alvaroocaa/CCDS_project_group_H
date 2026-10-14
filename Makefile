local-up:
	docker network create proxy 2>/dev/null || true
	docker compose -f basic/compose.yml up -d --build
	docker compose -f app/compose.yml up -d --build
	docker compose -f stats/compose.yml up -d --build

local-down:
	docker compose -f stats/compose.yml down
	docker compose -f app/compose.yml down
	docker compose -f basic/compose.yml down