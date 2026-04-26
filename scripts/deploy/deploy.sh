#!/usr/bin/env bash
# deploy.sh — ручной деплой MUZILLA на серверы.
# Использование:
#   bash deploy.sh --all          # деплой на все VM (VM-3 → VM-2 → VM-1)
#   bash deploy.sh --vm1          # деплой только на VM-1
#   bash deploy.sh --vm2          # деплой только на VM-2
#   bash deploy.sh --vm3          # деплой только на VM-3
#
# Перед использованием задай переменные в .env.deploy или экспортируй:
#   VM1_HOST, VM2_HOST, VM3_HOST, SSH_USER, SSH_PORT, SSH_KEY
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Загрузить переменные из файла, если есть
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$SCRIPT_DIR/.env.deploy" ]] && source "$SCRIPT_DIR/.env.deploy"

# Дефолты
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/muzilla_deploy}"

ssh_cmd() {
    local host="$1"
    shift
    ssh -o StrictHostKeyChecking=accept-new \
        -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$host" "$@"
}

deploy_vm3() {
    info "Деплою VM-3 (Data): $VM3_HOST"
    ssh_cmd "$VM3_HOST" bash -s <<'REMOTE'
cd /opt/muzilla
git pull origin main
docker compose -f compose.vm3-data.yml pull
docker compose -f compose.vm3-data.yml up -d
sleep 10
docker compose -f compose.vm3-data.yml exec -T postgres pg_isready -U muzilla
echo "VM-3 OK"
REMOTE
    info "VM-3 задеплоен"
}

deploy_vm2() {
    info "Деплою VM-2 (App): $VM2_HOST"
    ssh_cmd "$VM2_HOST" bash -s <<'REMOTE'
cd /opt/muzilla
git pull origin main
docker compose -f compose.vm2-app.yml pull
docker compose -f compose.vm2-app.yml up -d
sleep 5
docker compose -f compose.vm2-app.yml exec -T redis redis-cli ping
echo "VM-2 OK"
REMOTE
    info "VM-2 задеплоен"
}

deploy_vm1() {
    info "Деплою VM-1 (Edge): $VM1_HOST"
    ssh_cmd "$VM1_HOST" bash -s <<'REMOTE'
cd /opt/muzilla
git pull origin main
docker compose -f compose.vm1-edge.yml pull
docker compose -f compose.vm1-edge.yml up -d
sleep 10
docker compose -f compose.vm1-edge.yml exec -T main php artisan migrate --force
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan migrate --force
curl -sf http://localhost:8080/health || exit 1
echo "VM-1 OK"
REMOTE
    info "VM-1 задеплоен"
}

# Парсинг аргументов
case "${1:---help}" in
    --all)
        deploy_vm3
        deploy_vm2
        deploy_vm1
        info "Все серверы задеплоены"
        ;;
    --vm1) deploy_vm1 ;;
    --vm2) deploy_vm2 ;;
    --vm3) deploy_vm3 ;;
    *)
        echo "Использование: $0 {--all|--vm1|--vm2|--vm3}"
        exit 1
        ;;
esac
