#!/usr/bin/env bash
# vm2-app.sh — провижининг VM-2 (App): Redis, Reverb, очереди.
# Запуск: bash vm2-app.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "========================================"
echo " MUZILLA — Провижининг VM-2 (App)"
echo "========================================"
echo ""

# Сбор параметров
SSH_PORT=$(ask "SSH-порт (по умолчанию 22, рекомендуется сменить)" "22")
VM2_VLAN_IP=$(ask "Приватный IP этого сервера (VM-2) в VLAN (например 10.0.0.2)")
VM1_VLAN_IP=$(ask "Приватный IP VM-1 в VLAN (например 10.0.0.1)")

echo ""
info "Начинаю провижининг VM-2..."

# 1. Базовые пакеты
install_base_packages

# 2. Docker
install_docker

# 3. SSH hardening
harden_ssh "$SSH_PORT"

# 4. Firewall
# Redis (6379) и Reverb (8080) доступны только для VM-1 через VLAN
setup_firewall "$SSH_PORT" \
    "allow from $VM1_VLAN_IP to any port 6379 comment 'Redis from VM-1'" \
    "allow from $VM1_VLAN_IP to any port 8080 comment 'Reverb from VM-1'"

# 5. Swap
setup_swap "1G"

# 6. Клонирование репо и GHCR
clone_repo
setup_ghcr_login

echo ""
echo "========================================"
info "VM-2 (App) готов!"
echo "========================================"
echo ""
info "Следующие шаги:"
info "  1. cd /opt/muzilla"
info "  2. cp .env.prod.example .env && nano .env"
info "  3. make vm2"
info "  4. docker compose -f compose.vm2-app.yml exec redis redis-cli ping"
echo ""
warn "SSH-порт изменён на $SSH_PORT. Используй: ssh -p $SSH_PORT root@<IP>"
