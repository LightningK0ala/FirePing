.PHONY: help setup dev spec-dev test test-watch clean db-up db-ready db-down db-reset format check import-fires admin-grant admin-revoke admin-list fire-fetch fire-debug fire-count fire-test up down build logs

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Initial project setup (deps, create DB, migrate, hooks)
	docker exec app sh -c 'mix setup'
	@echo "Setting up Git hooks..."
	@./scripts/setup-hooks.sh

up: ## Start all services with Docker Compose
	docker-compose up -d

down: ## Stop all Docker Compose services
	docker-compose down

build: ## Build and start all services with Docker Compose
	docker-compose up -d --build

logs: ## Show logs from all Docker services
	docker-compose logs -f

dev: ## Start Phoenix development server with Docker
	docker-compose up

spec-dev: ## Start spec documentation server
	mdbook serve spec

test: db-ready ## Run tests
	docker exec app sh -c 'MIX_ENV=test DATABASE_URL=ecto://postgres:postgres@postgres:5432/app_test mix test'

test-watch: ## Run tests in watch mode
	docker exec app sh -c 'MIX_ENV=test DATABASE_URL=ecto://postgres:postgres@postgres:5432/app_test mix test.watch'

format: ## Format code
	docker exec app sh -c 'mix format'

check: ## Run code analysis (format check)
	docker exec app sh -c 'mix format --check-formatted'

clean: ## Clean build artifacts
	docker exec app sh -c 'mix clean'

db-up: ## Start database container
	docker-compose up -d postgres

db-ready: ## Ensure database container is up and ready to accept connections
	@docker-compose up -d postgres
	@echo "Waiting for Postgres to be ready..."
	@until docker-compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done; echo ready

db-down: ## Stop database container
	docker-compose down

db-reset: ## Reset database (drop, create, migrate) for both dev and test
	docker exec app sh -c 'mix ecto.drop && mix ecto.create && mix ecto.migrate'
	docker exec app sh -c 'MIX_ENV=test mix ecto.drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate'

db-seed: ## Run database seeds
	docker exec app sh -c 'mix run priv/repo/seeds.exs'

import-fires: ## Import sample NASA FIRMS fire data from CSV
	docker exec app sh -c 'mix import_sample_fires'

admin-grant: ## Grant admin privileges to user (usage: make admin-grant user@example.com)
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then echo "Usage: make admin-grant user@example.com"; exit 1; fi
	docker exec app sh -c 'mix admin.grant $(filter-out $@,$(MAKECMDGOALS))'

admin-revoke: ## Revoke admin privileges from user (usage: make admin-revoke user@example.com)
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then echo "Usage: make admin-revoke user@example.com"; exit 1; fi
	docker exec app sh -c 'mix admin.revoke $(filter-out $@,$(MAKECMDGOALS))'

admin-list: ## List all admin users
	docker exec app sh -c 'mix admin.list'

fire-fetch: ## Manually trigger FireFetch job (usage: make fire-fetch or make fire-fetch days=3)
	@if [ -n "$(days)" ]; then \
		docker exec app sh -c 'mix fire_fetch $(days)'; \
	else \
		docker exec app sh -c 'mix fire_fetch'; \
	fi

fire-debug: ## Debug NASA FIRMS API response (usage: make fire-debug or make fire-debug days=3)
	@if [ -n "$(days)" ]; then \
		docker exec app sh -c 'mix fire_debug $(days)'; \
	else \
		docker exec app sh -c 'mix fire_debug'; \
	fi

fire-count: ## Show fire database statistics
	docker exec app sh -c 'mix fire_count'

fire-test: ## Test FireFetch logic synchronously with detailed logging
	docker exec app sh -c 'mix fire_test'

%:
	@:
