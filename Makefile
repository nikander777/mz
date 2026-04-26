.PHONY: help

STAGE := docker compose -f compose.stage.yml
DEV   := docker compose

help:
	@echo "=== Dev (локальный build, docker-compose.yml) ==="
	@echo "  make dev-up        — поднять dev-стек (edge :8088)"
	@echo "  make dev-down      — остановить dev-стек"
	@echo "  make dev-build     — пересобрать dev-образы"
	@echo "  make dev-logs      — логи dev"
	@echo ""
	@echo "=== Stage (single-host, compose.stage.yml) ==="
	@echo "  make build         — локально собрать образы stage"
	@echo "  make pull          — обновить образы из GHCR"
	@echo "  make up            — поднять stage"
	@echo "  make down          — остановить stage"
	@echo "  make deploy        — pull + up -d"
	@echo "  make logs          — логи stage"
	@echo "  make migrate       — artisan migrate --force в main + discogs"
	@echo "  make seed-demo     — установить демо-данные (Faker + DemoSeeder)"
	@echo "  make shell-main    — bash в main"
	@echo "  make shell-discogs — bash в discogs"
	@echo ""
	@echo "=== Prod (3 VM) ==="
	@echo "  make vm1 / vm2 / vm3           — pull + up-d на каждой VM"
	@echo "  make vm1-logs / vm2-logs / vm3-logs"
	@echo ""
	@echo "=== Провижининг ==="
	@echo "  make provision-vm1/vm2/vm3     — первоначальная настройка серверов"
	@echo ""
	@echo "=== Деплой и мониторинг ==="
	@echo "  make deploy-all                — деплой на все серверы"
	@echo "  make deploy-vm1/vm2/vm3        — деплой на конкретную VM"
	@echo "  make health                    — проверка здоровья всех сервисов"

# ===== Dev =====
.PHONY: dev-up dev-down dev-build dev-logs
dev-up:
	$(DEV) up -d

dev-down:
	$(DEV) down

dev-build:
	$(DEV) build

dev-logs:
	$(DEV) logs -f --tail=200

# ===== Stage =====
.PHONY: build up down pull deploy logs migrate shell-main shell-discogs

build:
	$(STAGE) build

up:
	$(STAGE) up -d

down:
	$(STAGE) down

pull:
	$(STAGE) pull

deploy: pull up

logs:
	$(STAGE) logs -f --tail=200

migrate:
	$(STAGE) exec main php artisan migrate --force
	$(STAGE) exec discogs php artisan migrate --force

seed-demo:
	@echo ">>> Установка fakerphp/faker (нужен для seed-фабрик)..."
	$(STAGE) exec main composer require --dev fakerphp/faker --no-interaction
	@echo ">>> Seeding main (DemoSeeder + Categories/Brands/Products/News)..."
	$(STAGE) exec main php artisan db:seed --force
	@echo ">>> Seeding discogs (test user)..."
	$(STAGE) exec -T discogs php artisan tinker --execute='\App\Models\User::firstOrCreate(["email" => "test@example.com"], ["name" => "Test User", "password" => bcrypt("password123")]);'
	@echo ">>> Перезапись паролей demo-аккаунтов в main..."
	$(STAGE) exec -T main php artisan tinker --execute='\App\Models\User::where("email","test@example.com")->first()->update(["password" => \Hash::make("password123")]); $$a = \App\Models\User::where("email","admin@muzilla.ru")->first(); if ($$a) { $$a->update(["password" => \Hash::make("password")]); }'
	@echo ""
	@echo "Demo-данные готовы. Аккаунты:"
	@echo "  admin@muzilla.ru   / password    (super-admin)"
	@echo "  test@example.com   / password123 (buyer)"
	@echo "  alex@musicstore.com / password123 (seller)"
	@echo "  info@musicmarket.ru / store123    (store)"

shell-main:
	$(STAGE) exec main bash

shell-discogs:
	$(STAGE) exec discogs bash

# ===== Prod (3 VM) =====
.PHONY: vm1 vm2 vm3 vm1-logs vm2-logs vm3-logs

vm1:
	docker compose -f compose.vm1-edge.yml pull && docker compose -f compose.vm1-edge.yml up -d

vm2:
	docker compose -f compose.vm2-app.yml pull && docker compose -f compose.vm2-app.yml up -d

vm3:
	docker compose -f compose.vm3-data.yml pull && docker compose -f compose.vm3-data.yml up -d

vm1-logs:
	docker compose -f compose.vm1-edge.yml logs -f --tail=200

vm2-logs:
	docker compose -f compose.vm2-app.yml logs -f --tail=200

vm3-logs:
	docker compose -f compose.vm3-data.yml logs -f --tail=200

# ===== Провижининг =====
.PHONY: provision-vm1 provision-vm2 provision-vm3

provision-vm1:
	bash scripts/provision/vm1-edge.sh

provision-vm2:
	bash scripts/provision/vm2-app.sh

provision-vm3:
	bash scripts/provision/vm3-data.sh

# ===== Деплой и мониторинг =====
.PHONY: deploy-all deploy-vm1 deploy-vm2 deploy-vm3 health

deploy-all:
	bash scripts/deploy/deploy.sh --all

deploy-vm1:
	bash scripts/deploy/deploy.sh --vm1

deploy-vm2:
	bash scripts/deploy/deploy.sh --vm2

deploy-vm3:
	bash scripts/deploy/deploy.sh --vm3

health:
	bash scripts/deploy/health-check.sh --ssh
