#!/usr/bin/env bash
# common.sh — общие функции провижининга MUZILLA.
# Подключается через: source "$(dirname "$0")/common.sh"
set -euo pipefail

# ==================== Цвета ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ==================== Ввод данных ====================
ask() {
    local prompt="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        read -rp "$prompt: " value
        echo "$value"
    fi
}

# ==================== Docker ====================
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker уже установлен: $(docker --version)"
        return
    fi

    info "Устанавливаю Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    info "Docker установлен: $(docker --version)"
}

# ==================== SSH Hardening ====================
harden_ssh() {
    local ssh_port="${1:-22}"

    info "Усиливаю SSH (порт: $ssh_port)..."

    # КРИТИЧНО: убедиться что у root есть authorized_keys, иначе после
    # отключения PasswordAuthentication пользователь себя выкинет.
    if [[ ! -s /root/.ssh/authorized_keys ]]; then
        error "У /root/.ssh/authorized_keys нет SSH-ключей."
        error "Если ты зашёл по паролю, отключение PasswordAuthentication"
        error "выкинет тебя из SSH без возможности зайти повторно."
        error ""
        error "Сначала залей свой публичный ключ с локальной машины:"
        error "  ssh-copy-id root@<IP>"
        error "или вручную добавь его в /root/.ssh/authorized_keys"
        return 1
    fi

    # Бэкап оригинального конфига
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    sed -i "s/^#\?Port .*/Port $ssh_port/" /etc/ssh/sshd_config
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # Проверка синтаксиса до рестарта — иначе можно сломать SSH-сервис
    if ! sshd -t 2>/dev/null; then
        error "Синтаксис /etc/ssh/sshd_config невалиден — откатываю изменения"
        mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        return 1
    fi

    # На Ubuntu 24.04 unit называется ssh.service (sshd — alias)
    systemctl restart ssh
    info "SSH усилен. Порт: $ssh_port, пароли отключены."
}

# ==================== Firewall ====================
setup_firewall() {
    local ssh_port="$1"
    shift
    local extra_rules=("$@")  # формат: "allow from <IP> to any port <PORT>"

    info "Настраиваю firewall (ufw)..."
    apt-get install -y -qq ufw

    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$ssh_port"/tcp comment 'SSH'

    for rule in "${extra_rules[@]}"; do
        eval "ufw $rule"
    done

    echo "y" | ufw enable
    info "Firewall активен. Правила:"
    ufw status numbered
}

# ==================== Swap ====================
setup_swap() {
    local size="${1:-2G}"

    if swapon --show | grep -q '/swapfile'; then
        info "Swap уже настроен"
        return
    fi

    info "Создаю swap ($size)..."
    fallocate -l "$size" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Идемпотентность: добавляем строку только если её ещё нет
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Снижаем swappiness — swap только в крайнем случае
    sysctl vm.swappiness=10
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

    info "Swap $size активен, swappiness=10"
}

# ==================== GHCR Login ====================
setup_ghcr_login() {
    local token
    info "Настраиваю доступ к GHCR (GitHub Container Registry)..."
    info "Нужен Personal Access Token с правом read:packages"
    info "Создай тут: https://github.com/settings/tokens/new?scopes=read:packages"
    token=$(ask "Вставь GHCR токен")

    echo "$token" | docker login ghcr.io -u nikander777 --password-stdin
    info "GHCR login успешен"
}

# ==================== Clone Repo ====================
clone_repo() {
    local repo_url="${1:-https://github.com/nikander777/mz.git}"
    local target="/opt/muzilla"

    if [[ -d "$target/.git" ]]; then
        info "Репо уже клонировано в $target"
        cd "$target" && git pull origin main
        return
    fi

    info "Клонирую репо в $target..."
    git clone "$repo_url" "$target"
    info "Репо клонировано"
}

# ==================== Общие утилиты ====================
install_base_packages() {
    info "Устанавливаю базовые пакеты..."
    apt-get update -qq
    apt-get install -y -qq \
        git curl wget htop iotop unzip \
        apt-transport-https software-properties-common
}

generate_pg_ssl_certs() {
    # Генерирует самоподписанный сертификат для PostgreSQL SSL
    local cert_dir="$1"
    info "Генерирую SSL-сертификат для PostgreSQL..."
    mkdir -p "$cert_dir"
    openssl req -new -x509 -days 3650 -nodes \
        -out "$cert_dir/server.crt" \
        -keyout "$cert_dir/server.key" \
        -subj "/CN=muzilla-postgres"
    chmod 600 "$cert_dir/server.key"
    chmod 644 "$cert_dir/server.crt"
    # PostgreSQL требует владельца 999 (postgres user в контейнере)
    chown 999:999 "$cert_dir/server.key" "$cert_dir/server.crt"
    info "SSL-сертификат создан"
}
