#!/usr/bin/env bash
# switch-domain.sh — перевод прода на новый публичный домен.
#
# Запускается С ЛОКАЛКИ, ходит по SSH на VM-1 и VM-2.
#
#   bash scripts/deploy/switch-domain.sh --check     # только проверки, ничего не меняет
#   bash scripts/deploy/switch-domain.sh --apply     # переключить прямо сейчас
#   bash scripts/deploy/switch-domain.sh --arm       # ждать переезда DNS и переключить самому
#   bash scripts/deploy/switch-domain.sh --disarm    # снять сторожа
#   bash scripts/deploy/switch-domain.sh --watch-log # что видит сторож
#   bash scripts/deploy/switch-domain.sh --rollback  # вернуть предыдущий .env и Caddyfile
#
# Порядок для переезда — либо вручную:
#   1. --check  — убедиться, что A-записи NEW_DOMAIN и www уже смотрят на VM-1;
#   2. поменять DNS, если ещё не поменян, дождаться зелёного --check;
#   3. --apply  — env на обеих VM, Caddyfile, пересоздание контейнеров, прогрев.
#
# Либо без дежурства у монитора: --arm ставит на обе VM сторожа (cron раз в
# минуту, scripts/deploy/domain-watch.sh). Он ждёт, пока A-запись переедет на
# VM-1, и делает ровно то же, что --apply, в ту же минуту. После успеха
# снимает себя сам; если DNS не переехал за 48 часов — тоже снимает.
#
# Почему нельзя переключить env ДО смены DNS: публичный адрес API зашит в
# клиентский бандл Nuxt (NUXT_PUBLIC_API_URL). Пока NEW_DOMAIN резолвится в
# старый сайт, браузер будет ходить туда за /api/* и прод ляжет.
#
# Переменные — в scripts/deploy/.env.deploy (gitignored) или в окружении:
#   VM1_HOST, VM2_HOST, SSH_USER, SSH_PORT, SSH_KEY
#   NEW_DOMAIN (по умолчанию muzilla.ru), OLD_DOMAIN (по умолчанию new.muzilla.ru)
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$SCRIPT_DIR/.env.deploy" ]] && source "$SCRIPT_DIR/.env.deploy"

SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
NEW_DOMAIN="${NEW_DOMAIN:-muzilla.ru}"
OLD_DOMAIN="${OLD_DOMAIN:-new.muzilla.ru}"
STAMP="$(date +%Y%m%d-%H%M%S)"

: "${VM1_HOST:?Не задан VM1_HOST (scripts/deploy/.env.deploy)}"
: "${VM2_HOST:?Не задан VM2_HOST (scripts/deploy/.env.deploy)}"

ssh_cmd() {
    local host="$1"; shift
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
        -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$host" "$@"
}

# ===== Проверки =====

check_dns() {
    local failed=0
    info "DNS: где сейчас $NEW_DOMAIN"
    for name in "$NEW_DOMAIN" "www.$NEW_DOMAIN"; do
        # Резолвим с самой VM-1: её резолвер и увидит клиент, и увидит Caddy
        # при выпуске сертификата.
        local ip
        ip=$(ssh_cmd "$VM1_HOST" "getent hosts $name | awk '{print \$1}' | head -1" || true)
        if [[ "$ip" == "$VM1_HOST" ]]; then
            info "  $name → $ip (VM-1) ✓"
        else
            error "  $name → ${ip:-нет записи} (ожидается $VM1_HOST)"
            failed=1
        fi
    done
    # VM-2 ходит в discogs через публичный домен (DISCOGS_API_URL=https://$PUBLIC_HOST),
    # поэтому её резолвер тоже должен видеть новый адрес.
    local ip2
    ip2=$(ssh_cmd "$VM2_HOST" "getent hosts $NEW_DOMAIN | awk '{print \$1}' | head -1" || true)
    if [[ "$ip2" == "$VM1_HOST" ]]; then
        info "  $NEW_DOMAIN с VM-2 → $ip2 ✓"
    else
        error "  $NEW_DOMAIN с VM-2 → ${ip2:-нет записи} (ожидается $VM1_HOST)"
        failed=1
    fi
    return $failed
}

check_current() {
    info "Текущее состояние прода ($OLD_DOMAIN)"
    local code
    code=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "https://$OLD_DOMAIN/health" || echo 000)
    echo "  https://$OLD_DOMAIN/health → $code"
    ssh_cmd "$VM1_HOST" "grep -E '^(MAIN_APP_URL|PUBLIC_HOST|SESSION_DOMAIN|SANCTUM_STATEFUL_DOMAINS|NUXT_BACKEND_BASE_URL)=' /opt/muzilla/.env" || true
}

smoke() {
    local base="https://$1"
    local rc=0
    info "Прогон $base"
    for path_expect in "/health:200" "/:200" "/api/auth/me:401" "/api/disco/releases?per_page=1:200"; do
        local path="${path_expect%:*}" expect="${path_expect##*:}"
        local code
        code=$(curl -so /dev/null -w "%{http_code}" --max-time 20 "$base$path" || echo 000)
        if [[ "$code" == "$expect" ]]; then
            info "  $path → $code ✓"
        else
            error "  $path → $code (ожидался $expect)"
            rc=1
        fi
    done
    return $rc
}

# ===== Применение =====

patch_env() {
    local host="$1" label="$2"
    info "$label: правлю /opt/muzilla/.env (бэкап .env.bak-domain-$STAMP)"
    ssh_cmd "$host" bash -s <<REMOTE
set -e
cd /opt/muzilla
cp .env .env.bak-domain-$STAMP
sed -i "s/$OLD_DOMAIN/$NEW_DOMAIN/g" .env
# www — отдельным доменом в списке stateful: Caddy редиректит его на apex,
# но пока редирект не отработал, cookie-аутентификация должна быть разрешена.
sed -i "s/^SANCTUM_STATEFUL_DOMAINS=.*/SANCTUM_STATEFUL_DOMAINS=$NEW_DOMAIN,www.$NEW_DOMAIN/" .env
grep -E '^(MAIN_APP_URL|DISCOGS_APP_URL|REVERB_HOST|NUXT_BACKEND_BASE_URL|SANCTUM_STATEFUL_DOMAINS|SESSION_DOMAIN|PUBLIC_HOST|APP_FRONTEND_URL|VKID_REDIRECT_URI|MONETA_.*URL)=' .env
REMOTE
}

# Caddyfile в два приёма — тем же порядком, что у сторожа:
#   interim — оба домена ОБСЛУЖИВАЮТ (клиентский бандл ещё ходит на старый);
#   final   — старое имя редиректит, кроме вебхуков.
# Между ними ждём сертификат: пока его нет, ничего необратимого не сделано.
patch_caddy() {
    local mode="$1"
    info "VM-1: Caddyfile ($mode)"
    ssh_cmd "$VM1_HOST" bash -s <<REMOTE
set -e
[[ -f /etc/caddy/Caddyfile.bak-$STAMP ]] || cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-$STAMP
cat > /etc/caddy/Caddyfile <<'CADDY'
$NEW_DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up Host {host}
    }
    encode gzip
}
CADDY
if [[ "$mode" == "interim" ]]; then
cat >> /etc/caddy/Caddyfile <<'CADDY'

www.$NEW_DOMAIN, $OLD_DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up Host {host}
    }
    encode gzip
}
CADDY
else
# Вебхуки БПА/НКО прописаны в кабинетах на старом домене, а POST за 301 не
# идёт — тело потеряется. Их проксируем, остальное редиректим.
cat >> /etc/caddy/Caddyfile <<'CADDY'

www.$NEW_DOMAIN, $OLD_DOMAIN {
    handle /api/webhook/* {
        reverse_proxy 127.0.0.1:8080 {
            header_up X-Real-IP {remote_host}
            header_up Host {host}
        }
    }
    handle {
        redir https://$NEW_DOMAIN{uri} permanent
    }
}
CADDY
fi
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
systemctl reload caddy
echo "Caddyfile: $mode, reload ok"
REMOTE
}

restore_caddy() {
    warn "VM-1: возвращаю прежний Caddyfile"
    ssh_cmd "$VM1_HOST" "cp /etc/caddy/Caddyfile.bak-$STAMP /etc/caddy/Caddyfile && systemctl reload caddy && echo восстановлен"
}

# Сертификат Let's Encrypt на новый домен. Резолвим принудительно в себя:
# локальный кеш VM-1 может ещё держать старый IP.
wait_cert() {
    info "Жду сертификат на $NEW_DOMAIN (до 200 с)"
    ssh_cmd "$VM1_HOST" bash -s <<REMOTE
for i in \$(seq 1 40); do
    if curl -sf --max-time 5 --resolve "$NEW_DOMAIN:443:127.0.0.1" "https://$NEW_DOMAIN/health" | grep -q '^ok\$'; then
        echo "сертификат получен на попытке \$i"
        exit 0
    fi
    sleep 5
done
echo "сертификат не поднялся"
exit 1
REMOTE
}

recreate() {
    info "VM-1: пересоздаю контейнеры с новым env"
    ssh_cmd "$VM1_HOST" bash -s <<'REMOTE'
set -e
cd /opt/muzilla
docker compose -f compose.vm1-edge.yml up -d --force-recreate \
    nuxt main main-web discogs discogs-web edge
# Кеш конфига держит домен в bootstrap/cache/config.php: без сброса
# /sanctum/csrf-cookie отвечает 500 на новом домене.
docker compose -f compose.vm1-edge.yml exec -T main php artisan optimize:clear
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan optimize:clear
REMOTE

    info "VM-2: пересоздаю контейнеры с новым env"
    ssh_cmd "$VM2_HOST" bash -s <<'REMOTE'
set -e
cd /opt/muzilla
docker compose -f compose.vm2-app.yml up -d --force-recreate \
    reverb main-queue main-queue-media main-scheduler discogs-queue discogs-scheduler
docker compose -f compose.vm2-app.yml exec -T main-queue php artisan optimize:clear || true
REMOTE
}

patch_monitor() {
    info "VM-1: MONITOR_URL мониторинга"
    ssh_cmd "$VM1_HOST" bash -s <<REMOTE
set -e
f=/opt/muzilla/scripts/deploy/.env.deploy
[[ -f \$f ]] || exit 0
sed -i "s#^MONITOR_URL=.*#MONITOR_URL=https://$NEW_DOMAIN#" \$f
grep '^MONITOR_URL=' \$f
REMOTE
}

rollback() {
    warn "Откат: последний бэкап .env и Caddyfile"
    ssh_cmd "$VM1_HOST" bash -s <<'REMOTE'
set -e
cd /opt/muzilla
last=$(ls -1t .env.bak-domain-* 2>/dev/null | head -1)
[[ -n "$last" ]] || { echo "нет бэкапа .env"; exit 1; }
cp "$last" .env && echo "восстановлен $last"
lastc=$(ls -1t /etc/caddy/Caddyfile.bak-* 2>/dev/null | head -1)
[[ -n "$lastc" ]] && cp "$lastc" /etc/caddy/Caddyfile && systemctl reload caddy && echo "восстановлен $lastc"
docker compose -f compose.vm1-edge.yml up -d --force-recreate nuxt main main-web discogs discogs-web edge
docker compose -f compose.vm1-edge.yml exec -T main php artisan optimize:clear
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan optimize:clear
REMOTE
    ssh_cmd "$VM2_HOST" bash -s <<'REMOTE'
set -e
cd /opt/muzilla
last=$(ls -1t .env.bak-domain-* 2>/dev/null | head -1)
[[ -n "$last" ]] || { echo "нет бэкапа .env"; exit 1; }
cp "$last" .env && echo "восстановлен $last"
docker compose -f compose.vm2-app.yml up -d --force-recreate \
    reverb main-queue main-queue-media main-scheduler discogs-queue discogs-scheduler
REMOTE
    info "Откат выполнен"
}

arm() {
    local script="$SCRIPT_DIR/domain-watch.sh"
    [[ -f "$script" ]] || { error "нет $script"; exit 1; }

    for pair in "$VM1_HOST:vm1" "$VM2_HOST:vm2"; do
        local host="${pair%:*}" role="${pair##*:}"
        info "Ставлю сторожа на $role ($host)"
        scp -q -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" -P "$SSH_PORT" \
            "$script" "$SSH_USER@$host:/usr/local/sbin/muzilla-domain-watch.sh"
        ssh_cmd "$host" bash -s <<REMOTE
set -e
chmod +x /usr/local/sbin/muzilla-domain-watch.sh
cat > /etc/muzilla-domain-watch.env <<CONF
NEW_DOMAIN=$NEW_DOMAIN
OLD_DOMAIN=$OLD_DOMAIN
TARGET_IP=$VM1_HOST
ROLE=$role
DEADLINE=\$(date -d '+48 hours' +%s)
CONF
chmod 600 /etc/muzilla-domain-watch.env
mkdir -p /var/lib/muzilla-domain-watch
( crontab -l 2>/dev/null | grep -v muzilla-domain-watch; \
  echo '* * * * * flock -n /run/muzilla-domain-watch.lock /usr/local/sbin/muzilla-domain-watch.sh >> /var/log/muzilla-domain-switch.log 2>&1' \
) | crontab -
crontab -l | grep muzilla-domain-watch
REMOTE
    done
    echo ""
    info "Сторожа вооружены. Триггер — A-записи $NEW_DOMAIN и www.$NEW_DOMAIN → $VM1_HOST"
    info "Смотреть: bash $0 --watch-log     Снять: bash $0 --disarm"
}

disarm() {
    for host in "$VM1_HOST" "$VM2_HOST"; do
        info "Снимаю сторожа на $host"
        ssh_cmd "$host" bash -s <<'REMOTE'
crontab -l 2>/dev/null | grep -v muzilla-domain-watch | crontab - || true
rm -f /etc/muzilla-domain-watch.env /usr/local/sbin/muzilla-domain-watch.sh
echo "снят"
REMOTE
    done
}

watch_log() {
    for pair in "$VM1_HOST:VM-1" "$VM2_HOST:VM-2"; do
        local host="${pair%:*}" label="${pair##*:}"
        echo "===== $label ($host) ====="
        ssh_cmd "$host" bash -s <<'REMOTE'
if [[ -f /etc/muzilla-domain-watch.env ]]; then
    echo "сторож: вооружён"
else
    echo "сторож: снят (переключил или не ставился)"
fi
tail -n 15 /var/log/muzilla-domain-switch.log 2>/dev/null || echo "(лога пока нет)"
REMOTE
        echo ""
    done
}

case "${1:---check}" in
    --check)
        check_current
        echo ""
        if check_dns; then
            info "DNS готов — можно запускать --apply"
        else
            warn "DNS ещё не переключен на VM-1. --apply запускать РАНО."
            exit 1
        fi
        ;;
    --apply)
        check_dns || { error "DNS не готов, прерываюсь"; exit 1; }
        patch_caddy interim
        if ! wait_cert; then
            error "Сертификат на $NEW_DOMAIN не выпустился — откат, прод не тронут"
            restore_caddy
            exit 1
        fi
        patch_env "$VM1_HOST" "VM-1"
        patch_env "$VM2_HOST" "VM-2"
        recreate
        patch_caddy final
        patch_monitor
        echo ""
        info "Жду 20 с, пока поднимется Nuxt SSR..."
        sleep 20
        smoke "$NEW_DOMAIN" || warn "Прогон нового домена с ошибками — смотри логи"
        echo ""
        code=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "https://$OLD_DOMAIN/" || echo 000)
        info "Редирект $OLD_DOMAIN → $code (ожидается 301)"
        echo ""
        info "Готово. Что осталось СНАРУЖИ (в кабинетах):"
        echo "  • VK ID (id.vk.ru): redirect URI https://$NEW_DOMAIN/api/auth/vk/callback"
        echo "  • БПА ПэйЭниВей (mp@payanyway.ru): адрес уведомлений на $NEW_DOMAIN"
        echo "  • НКО МОНЕТА ЛК2: адрес коллбека на $NEW_DOMAIN"
        echo "  • Яндекс.Метрика / Top.Mail.Ru: адрес сайта"
        echo "  • Яндекс.Вебмастер / Search Console: переезд сайта, главное зеркало"
        ;;
    --arm)
        check_current
        echo ""
        arm
        ;;
    --disarm)
        disarm
        ;;
    --watch-log)
        watch_log
        ;;
    --rollback)
        rollback
        ;;
    *)
        echo "Использование: $0 {--check|--apply|--arm|--disarm|--watch-log|--rollback}"
        exit 1
        ;;
esac
