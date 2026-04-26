#!/usr/bin/env bash
# health-check.sh — проверка здоровья всех сервисов MUZILLA.
# Использование:
#   bash health-check.sh                # проверить через SSH
#   bash health-check.sh --local        # проверить локально (запускать на VM-1)
#   bash health-check.sh --url https://mzt.nadev.ru  # проверить по URL
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ERRORS=$((ERRORS + 1)); }
ERRORS=0

echo "========================================="
echo " MUZILLA — Health Check"
echo "========================================="

# Загрузить переменные
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$SCRIPT_DIR/.env.deploy" ]] && source "$SCRIPT_DIR/.env.deploy"

SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/muzilla_deploy}"

ssh_cmd() {
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
        -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$1" "${@:2}" 2>/dev/null
}

check_url() {
    local url="$1" desc="$2"
    local code
    code=$(curl -so /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|401|302)$ ]]; then
        ok "$desc ($code)"
    else
        fail "$desc (HTTP $code)"
    fi
}

case "${1:---ssh}" in
    --url)
        BASE_URL="${2:?Укажи URL: --url https://mzt.nadev.ru}"
        echo ""
        echo "Проверяю $BASE_URL..."
        check_url "$BASE_URL/" "Nuxt SSR (главная)"
        check_url "$BASE_URL/health" "Edge health endpoint"
        check_url "$BASE_URL/api/auth/me" "Laravel API (ожидаем 401)"
        ;;

    --local)
        echo ""
        echo "Локальная проверка (запускай на VM-1)..."
        check_url "http://localhost:8080/health" "Edge nginx health"
        check_url "http://localhost:8080/" "Nuxt SSR"
        check_url "http://localhost:8080/api/auth/me" "Laravel API"
        ;;

    --ssh)
        echo ""
        echo "Проверяю VM-3 ($VM3_HOST)..."
        if ssh_cmd "$VM3_HOST" "docker compose -f /opt/muzilla/compose.vm3-data.yml exec -T postgres pg_isready -U muzilla" >/dev/null 2>&1; then
            ok "PostgreSQL accepting connections"
        else
            fail "PostgreSQL not ready"
        fi

        echo ""
        echo "Проверяю VM-2 ($VM2_HOST)..."
        if ssh_cmd "$VM2_HOST" "docker compose -f /opt/muzilla/compose.vm2-app.yml exec -T redis redis-cli ping" 2>/dev/null | grep -q PONG; then
            ok "Redis PONG"
        else
            fail "Redis not responding"
        fi

        echo ""
        echo "Проверяю VM-1 ($VM1_HOST)..."
        if ssh_cmd "$VM1_HOST" "curl -sf http://localhost:8080/health" >/dev/null 2>&1; then
            ok "Edge health"
        else
            fail "Edge health failed"
        fi
        if ssh_cmd "$VM1_HOST" "curl -sf http://localhost:8080/" >/dev/null 2>&1; then
            ok "Nuxt SSR"
        else
            fail "Nuxt SSR failed"
        fi
        ;;

    *)
        echo "Использование: $0 {--ssh|--local|--url <URL>}"
        exit 1
        ;;
esac

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}Все проверки пройдены${NC}"
else
    echo -e "${RED}Ошибок: $ERRORS${NC}"
    exit 1
fi
