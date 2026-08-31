#!/usr/bin/env bash
# monitor.sh — мониторинг MUZILLA с алертами в Telegram.
# Добавь в cron: */5 * * * * /opt/muzilla/scripts/deploy/monitor.sh
#
# Переменные (задай в .env.deploy или экспортируй):
#   MONITOR_URL       — URL для проверки (по умолчанию боевой домен)
#   TELEGRAM_BOT_TOKEN — токен Telegram бота
#   TELEGRAM_CHAT_ID   — ID чата для алертов
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$SCRIPT_DIR/.env.deploy" ]] && source "$SCRIPT_DIR/.env.deploy"

# Домен mzt.nadev.ru отключён — проверки по нему молча уходили в никуда.
MONITOR_URL="${MONITOR_URL:-https://new.muzilla.ru}"
STATE_FILE="/tmp/muzilla_monitor_state"

send_telegram() {
    local message="$1"
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -sf -X POST \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$message" \
            -d parse_mode="HTML" \
            >/dev/null 2>&1 || true
    fi
}

check_service() {
    local url="$1" name="$2" expected_codes="$3"
    local code
    code=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null || echo "000")

    if echo "$expected_codes" | grep -qw "$code"; then
        return 0
    else
        return 1
    fi
}

ERRORS=""
PREV_STATE="ok"
[[ -f "$STATE_FILE" ]] && PREV_STATE=$(cat "$STATE_FILE")

# Проверки
check_service "$MONITOR_URL/health" "Edge" "200" || ERRORS+="Edge nginx down\n"
check_service "$MONITOR_URL/" "Nuxt" "200" || ERRORS+="Nuxt SSR down\n"
check_service "$MONITOR_URL/api/auth/me" "Laravel" "200 401" || ERRORS+="Laravel API down\n"

# Сквозная проверка дискографии: nuxt → discogs → Meilisearch.
# Проверок выше недостаточно — при мёртвом Meili главная и /api/auth/me
# продолжают отдавать 200, и авария 16.06.2026 так и осталась незамеченной
# два месяца. Здесь же 503 вылезет сразу.
check_service "$MONITOR_URL/api/disco/releases?per_page=1" "Дискография" "200" || ERRORS+="Дискография down (Meilisearch?)\n"

# Глобальный поиск деградирует мягко: 200 с пустой выдачей и текстом ошибки
# в теле, поэтому кода ответа мало — смотрим тело.
if curl -s --max-time 15 "$MONITOR_URL/api/search?q=beatles" 2>/dev/null | grep -q '"error"'; then
    ERRORS+="Глобальный поиск отдаёт ошибку в теле\n"
fi

if [[ -n "$ERRORS" ]]; then
    echo "down" > "$STATE_FILE"
    # Алерт только при переходе ok → down (не спамим)
    if [[ "$PREV_STATE" == "ok" ]]; then
        send_telegram "$(printf "<b>MUZILLA DOWN</b>\n\n%b\nURL: %s\nTime: %s" "$ERRORS" "$MONITOR_URL" "$(date '+%Y-%m-%d %H:%M:%S')")"
    fi
else
    echo "ok" > "$STATE_FILE"
    # Уведомление о восстановлении
    if [[ "$PREV_STATE" == "down" ]]; then
        send_telegram "$(printf "<b>MUZILLA RESTORED</b>\n\nAll services back online.\nURL: %s\nTime: %s" "$MONITOR_URL" "$(date '+%Y-%m-%d %H:%M:%S')")"
    fi
fi
