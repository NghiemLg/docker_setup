# Lệnh tắt cho gs_env. Chạy trên HOST trong thư mục chứa file này.
COMPOSE   := docker compose
CONTAINER := gs_env

.PHONY: help setup x11 build rebuild up shell verify down restart logs ps

help:
	@echo "make setup    - dò GPU/driver, sinh .env, tạo workspace (chạy 1 lần)"
	@echo "make build    - build image gs-env:v1.0"
	@echo "make rebuild  - build lại từ đầu (không dùng cache)"
	@echo "make up       - khởi động container nền"
	@echo "make shell    - vào zsh trong container"
	@echo "make verify   - kiểm tra GPU, torch, gsplat, COLMAP, splat-transform"
	@echo "make down     - dừng và xóa container (dữ liệu trong ws/ vẫn giữ)"

setup:
	./host/setup_host.sh

x11:
	@./host/x11_auth.sh

build:
	@test -f .env || (echo "Chưa có .env -> chạy: make setup"; exit 1)
	DOCKER_BUILDKIT=1 $(COMPOSE) build

rebuild:
	DOCKER_BUILDKIT=1 $(COMPOSE) build --no-cache

up: x11
	$(COMPOSE) up -d

shell: x11
	docker exec -it $(CONTAINER) zsh

verify:
	docker exec -it $(CONTAINER) gs-verify

down:
	$(COMPOSE) down

restart: x11
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps
