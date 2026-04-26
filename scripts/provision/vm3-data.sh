#!/usr/bin/env bash
# vm3-data.sh — провижининг VM-3 (Data): PostgreSQL, Meilisearch, MinIO, бэкапы.
# Dedicated сервер, не в VLAN — связь через публичную сеть + firewall + SSL.
# Запуск: bash vm3-data.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "========================================"
echo " MUZILLA — Провижининг VM-3 (Data)"
echo "========================================"
echo ""

# Сбор параметров
SSH_PORT=$(ask "SSH-порт (по умолчанию 22, рекомендуется сменить)" "22")
VM1_PUBLIC_IP=$(ask "Публичный IP VM-1 (Edge)")
VM2_PUBLIC_IP=$(ask "Публичный IP VM-2 (App)")

echo ""
info "Начинаю провижининг VM-3..."

# 1. Базовые пакеты
install_base_packages

# 2. Docker
install_docker

# 3. SSH hardening
harden_ssh "$SSH_PORT"

# 4. Firewall
# Порты БД/поиска/хранилища открыты ТОЛЬКО для VM-1 и VM-2
setup_firewall "$SSH_PORT" \
    "allow from $VM1_PUBLIC_IP to any port 5432 comment 'PostgreSQL from VM-1'" \
    "allow from $VM2_PUBLIC_IP to any port 5432 comment 'PostgreSQL from VM-2'" \
    "allow from $VM1_PUBLIC_IP to any port 7700 comment 'Meilisearch from VM-1'" \
    "allow from $VM2_PUBLIC_IP to any port 7700 comment 'Meilisearch from VM-2'" \
    "allow from $VM1_PUBLIC_IP to any port 9000 comment 'MinIO API from VM-1'" \
    "allow from $VM1_PUBLIC_IP to any port 9001 comment 'MinIO Console from VM-1'"

# 5. Swap (2GB — подстраховка, основная работа на 128GB RAM)
setup_swap "2G"

# 6. Клонирование репо и GHCR
clone_repo
setup_ghcr_login

# 7. PostgreSQL SSL сертификат
# Сертификат монтируется в контейнер через pg_data volume
# PostgreSQL в контейнере видит его в /var/lib/postgresql/data/
PG_DATA_DIR="/var/lib/docker/volumes/muzilla-data_pg_data/_data"
info "PostgreSQL SSL: сертификат будет создан при первом запуске контейнера."
info "После первого 'make vm3' выполни:"
info "  docker compose -f compose.vm3-data.yml stop postgres"
info "  openssl req -new -x509 -days 3650 -nodes \\"
info "    -out $PG_DATA_DIR/server.crt \\"
info "    -keyout $PG_DATA_DIR/server.key \\"
info "    -subj '/CN=muzilla-postgres'"
info "  chmod 600 $PG_DATA_DIR/server.key"
info "  chown 999:999 $PG_DATA_DIR/server.key $PG_DATA_DIR/server.crt"
info "  docker compose -f compose.vm3-data.yml start postgres"

# 8. Директория для бэкапов
mkdir -p /opt/muzilla/backups
info "Директория бэкапов создана: /opt/muzilla/backups"

echo ""
echo "========================================"
info "VM-3 (Data) готов!"
echo "========================================"
echo ""
info "Следующие шаги:"
info "  1. cd /opt/muzilla"
info "  2. cp .env.prod.example .env && nano .env"
info "  3. make vm3"
info "  4. Настроить PostgreSQL SSL (см. инструкцию выше)"
info "  5. docker compose -f compose.vm3-data.yml exec postgres pg_isready -U muzilla"
echo ""
warn "SSH-порт изменён на $SSH_PORT. Используй: ssh -p $SSH_PORT root@<IP>"
warn "Порты БД открыты только для IP: $VM1_PUBLIC_IP и $VM2_PUBLIC_IP"
