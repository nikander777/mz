#!/usr/bin/env bash
# domain-watch.sh — одноразовый сторож смены домена. Живёт НА СЕРВЕРЕ,
# ставится и снимается через `switch-domain.sh --arm` / `--disarm`.
#
# Смысл: переключать env раньше DNS нельзя (публичный адрес API зашит в
# клиентский бандл Nuxt), а сертификат на новый домен Caddy не получит, пока
# A-запись смотрит в старое место. Сторож ждёт переезда A-записи и делает
# переключение сам — в ту же минуту, без участия человека.
#
# Ставится в cron раз в минуту, после успешного переключения снимает себя.
# Конфиг — /etc/muzilla-domain-watch.env (пишет --arm):
#   NEW_DOMAIN, OLD_DOMAIN, TARGET_IP, ROLE=vm1|vm2, DEADLINE=<epoch>
set -uo pipefail

CONF=/etc/muzilla-domain-watch.env
[[ -f "$CONF" ]] || exit 0
# shellcheck disable=SC1090
source "$CONF"

: "${NEW_DOMAIN:?}" "${OLD_DOMAIN:?}" "${TARGET_IP:?}" "${ROLE:?}" "${DEADLINE:?}"

export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

STATE_DIR=/var/lib/muzilla-domain-watch
STREAK_FILE="$STATE_DIR/streak"
REPO=/opt/muzilla
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STATE_DIR"

log() { echo "[$(date '+%F %T')] [$ROLE] $*"; }

notify() {
    local f="$REPO/scripts/deploy/.env.deploy"
    [[ -f "$f" ]] || return 0
    # shellcheck disable=SC1090
    source "$f" 2>/dev/null || return 0
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
    curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" -d text="$1" >/dev/null 2>&1 || true
}

disarm() {
    crontab -l 2>/dev/null | grep -v muzilla-domain-watch | crontab - || true
    rm -f "$CONF"
    log "сторож снят"
}

# ===== Предохранители =====

if [[ "$(date +%s)" -gt "$DEADLINE" ]]; then
    log "истёк срок ожидания DNS — снимаюсь, переключать вручную (switch-domain.sh --apply)"
    notify "MUZILLA: сторож смены домена снят по таймауту, DNS так и не переехал"
    disarm
    exit 0
fi

if ! grep -q "$OLD_DOMAIN" "$REPO/.env" 2>/dev/null; then
    log "в .env старого домена уже нет — видимо, переключили вручную; снимаюсь"
    disarm
    exit 0
fi

# ===== Триггер: A-запись у авторитативного NS =====
# Спрашиваем авторитативный сервер, а не локальный кеш: TTL 30 минут means
# кешированный ответ отстаёт от реальной смены на полчаса.

ns=$(dig +short NS "$NEW_DOMAIN" | head -1)
[[ -n "$ns" ]] || { log "не нашёл NS для $NEW_DOMAIN"; exit 0; }

a_apex=$(dig +short A "$NEW_DOMAIN" "@$ns" | tail -1)
a_www=$(dig +short A "www.$NEW_DOMAIN" "@$ns" | tail -1)

if [[ "$a_apex" != "$TARGET_IP" || "$a_www" != "$TARGET_IP" ]]; then
    echo 0 > "$STREAK_FILE"
    log "жду DNS: $NEW_DOMAIN=$a_apex www=$a_www (нужен $TARGET_IP)"
    exit 0
fi

# Две подряд удачные проверки — чтобы не среагировать на разовый глюк резолва.
streak=$(cat "$STREAK_FILE" 2>/dev/null || echo 0)
streak=$((streak + 1))
echo "$streak" > "$STREAK_FILE"
if [[ "$streak" -lt 2 ]]; then
    log "DNS переехал ($a_apex), жду подтверждения следующей минутой"
    exit 0
fi

resolvectl flush-caches 2>/dev/null || true

# ===== VM-1: Caddy + сертификат + env + контейнеры =====

write_caddy() {
    # $1 = interim | final
    local mode="$1"
    cat > /etc/caddy/Caddyfile <<CADDY
$NEW_DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up Host {host}
    }
    encode gzip
}
CADDY
    if [[ "$mode" == "interim" ]]; then
        # Пока env ещё на старом домене, старое имя ОБСЛУЖИВАЕТ, а не редиректит:
        # клиентский бандл там всё ещё ходит за /api/* на $OLD_DOMAIN.
        cat >> /etc/caddy/Caddyfile <<CADDY

www.$NEW_DOMAIN, $OLD_DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up Host {host}
    }
    encode gzip
}
CADDY
    else
        # Вебхуки БПА/НКО прописаны в кабинетах на старом домене, а POST за 301
        # не идёт — тело потеряется. Их проксируем, остальное редиректим.
        cat >> /etc/caddy/Caddyfile <<CADDY

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
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1
}

patch_env() {
    cd "$REPO" || return 1
    cp .env ".env.bak-domain-$STAMP"
    sed -i "s/$OLD_DOMAIN/$NEW_DOMAIN/g" .env
    sed -i "s/^SANCTUM_STATEFUL_DOMAINS=.*/SANCTUM_STATEFUL_DOMAINS=$NEW_DOMAIN,www.$NEW_DOMAIN/" .env
    log "env переписан, бэкап .env.bak-domain-$STAMP"
}

if [[ "$ROLE" == "vm1" ]]; then
    log "DNS подтверждён, переключаю VM-1"
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak-$STAMP"

    if ! write_caddy interim; then
        log "ОШИБКА: caddy validate не прошёл, откатываю Caddyfile"
        cp "/etc/caddy/Caddyfile.bak-$STAMP" /etc/caddy/Caddyfile
        exit 1
    fi
    systemctl reload caddy

    # Сертификат Let's Encrypt на новый домен. Резолвим принудительно в себя:
    # локальный кеш может ещё держать старый IP.
    ok=0
    for _ in $(seq 1 40); do
        if curl -sf --max-time 5 --resolve "$NEW_DOMAIN:443:127.0.0.1" \
                "https://$NEW_DOMAIN/health" | grep -q '^ok$'; then
            ok=1
            break
        fi
        sleep 5
    done
    if [[ "$ok" -ne 1 ]]; then
        log "ОШИБКА: сертификат на $NEW_DOMAIN не поднялся за 200 с — откат Caddyfile, повтор через минуту"
        cp "/etc/caddy/Caddyfile.bak-$STAMP" /etc/caddy/Caddyfile
        systemctl reload caddy
        exit 1
    fi
    log "https://$NEW_DOMAIN отвечает, сертификат есть"

    patch_env || exit 1

    cd "$REPO" || exit 1
    docker compose -f compose.vm1-edge.yml up -d --force-recreate \
        nuxt main main-web discogs discogs-web edge
    # Кеш конфига держит домен в bootstrap/cache/config.php: без сброса
    # /sanctum/csrf-cookie отвечает 500 на новом домене.
    docker compose -f compose.vm1-edge.yml exec -T main php artisan optimize:clear
    docker compose -f compose.vm1-edge.yml exec -T discogs php artisan optimize:clear

    write_caddy final && systemctl reload caddy
    log "Caddyfile переведён в финальный вид (старое имя → 301)"

    f="$REPO/scripts/deploy/.env.deploy"
    [[ -f "$f" ]] && sed -i "s#^MONITOR_URL=.*#MONITOR_URL=https://$NEW_DOMAIN#" "$f"

    sleep 15
    fails=""
    for pe in "/health:200" "/:200" "/api/auth/me:401" "/api/disco/releases?per_page=1:200"; do
        p="${pe%:*}"; want="${pe##*:}"
        code=$(curl -so /dev/null -w "%{http_code}" --max-time 20 "https://$NEW_DOMAIN$p" || echo 000)
        log "  $p → $code (ждали $want)"
        [[ "$code" == "$want" ]] || fails+="$p=$code "
    done
    code=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "https://$OLD_DOMAIN/" || echo 000)
    log "  редирект $OLD_DOMAIN → $code (ждали 301)"

    if [[ -n "$fails" ]]; then
        log "ВНИМАНИЕ: прогон с ошибками: $fails — откат: switch-domain.sh --rollback"
        notify "MUZILLA: домен переключён на $NEW_DOMAIN, но прогон с ошибками: $fails"
    else
        log "VM-1 переключена на $NEW_DOMAIN, прогон чистый"
        notify "MUZILLA: прод переключён на https://$NEW_DOMAIN, прогон чистый"
    fi
    disarm
    exit 0
fi

# ===== VM-2: ждёт, пока VM-1 отдаст /health по новому домену =====

if [[ "$ROLE" == "vm2" ]]; then
    # Гейт разом проверяет три вещи: VM-1 уже переключилась, сертификат живой,
    # и локальный резолвер VM-2 видит новый адрес (иначе фоновые задачи ходили
    # бы в discogs через https://$PUBLIC_HOST мимо цели).
    if ! curl -sf --max-time 10 "https://$NEW_DOMAIN/health" | grep -q '^ok$'; then
        log "жду, пока VM-1 отдаст https://$NEW_DOMAIN/health"
        exit 0
    fi

    log "VM-1 готова, переключаю VM-2"
    patch_env || exit 1

    cd "$REPO" || exit 1
    docker compose -f compose.vm2-app.yml up -d --force-recreate \
        reverb main-queue main-queue-media main-scheduler discogs-queue discogs-scheduler
    docker compose -f compose.vm2-app.yml exec -T main-queue php artisan optimize:clear || true

    log "VM-2 переключена на $NEW_DOMAIN"
    disarm
    exit 0
fi

log "неизвестная роль: $ROLE"
exit 1
