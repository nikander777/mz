#!/usr/bin/env bash
# vm1-edge.sh — провижининг VM-1 (Edge): Caddy + Docker.
# Запуск: bash vm1-edge.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "========================================"
echo " MUZILLA — Провижининг VM-1 (Edge)"
echo "========================================"
echo ""

# Сбор параметров
SSH_PORT=$(ask "SSH-порт (по умолчанию 22, рекомендуется сменить)" "22")
DOMAIN=$(ask "Домен сайта" "mzt.nadev.ru")
# IP VM-2/VM-3 здесь не нужны — VM-1 ходит к ним исходящими (default allow outgoing).
# Конкретные IP задаются в /opt/muzilla/.env (VM2_HOST/VM3_HOST).

echo ""
info "Начинаю провижининг VM-1..."

# 1. Базовые пакеты
install_base_packages

# 2. Docker
install_docker

# 3. SSH hardening
harden_ssh "$SSH_PORT"

# 4. Firewall
# Открываем: SSH, HTTP (80 для Caddy), HTTPS (443 для Caddy)
setup_firewall "$SSH_PORT" \
    "allow 80/tcp comment 'HTTP (Caddy)'" \
    "allow 443/tcp comment 'HTTPS (Caddy)'"

# 5. Swap
setup_swap "2G"

# 6. Установка Caddy
info "Устанавливаю Caddy..."
apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update -qq
apt-get install -y -qq caddy
info "Caddy установлен: $(caddy version)"

# 7. Настройка Caddyfile
info "Настраиваю Caddyfile для $DOMAIN..."
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
systemctl enable caddy
# Не запускаем caddy сразу — сначала нужно поднять Docker-стек
info "Caddy настроен. Запустить после docker: sudo systemctl start caddy"

# 8. Клонирование репо и GHCR
clone_repo
setup_ghcr_login

echo ""
echo "========================================"
info "VM-1 (Edge) готов!"
echo "========================================"
echo ""
info "Следующие шаги:"
info "  1. cd /opt/muzilla"
info "  2. cp .env.prod.example .env && nano .env"
info "  3. make vm1"
info "  4. sudo systemctl start caddy"
info "  5. curl -I https://$DOMAIN"
echo ""
warn "SSH-порт изменён на $SSH_PORT. Используй: ssh -p $SSH_PORT root@<IP>"
