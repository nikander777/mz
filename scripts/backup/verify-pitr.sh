#!/bin/bash
#
# Проверка восстановления main на момент времени (VM-3, ежедневно).
#
# Берёт последнюю базовую копию (pg-basebackup.sh) и сегменты WAL из бакета,
# поднимает одноразовый Postgres в режиме восстановления и проигрывает весь
# архив до конца. Сверяет строки ключевых таблиц с живой базой (не меньше 98%:
# живая база успевает уйти вперёд) и пишет в статус время последней
# восстановленной транзакции — фактическую точку восстановления.
#
# Восстановление на конкретный момент делается так же, плюс
# recovery_target_time — см. docs/deployment/backups.md.

JOB=pitr-main
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

WORK=/opt/muzilla/backups/pitr-verify
NAME="mz-pitr-verify-$$"
LIVE=muzilla-postgres-main-1

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1
    rm -rf "$WORK"
}

restore() {
    local status key started hours
    status=$(rc cat "bk:$BUCKET/status/base-main.json" 2>/dev/null)
    key=$(echo "$status" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
    started=$(echo "$status" | grep -o '"started_at":"[^"]*"' | cut -d'"' -f4)
    [ -n "$key" ] && [ -n "$started" ] || { JOB_ERROR="нет статуса базовой копии"; return 1; }

    rm -rf "$WORK" && mkdir -p "$WORK/data" "$WORK/wal"

    log "базовая копия $key"
    rc cat "bk:$BUCKET/$key" | tar -xz -C "$WORK/data" || { JOB_ERROR="не удалось распаковать $key"; return 1; }

    # Сегменты, выгруженные после начала копии (с запасом в час).
    hours=$(( ($(date +%s) - $(date -d "$started" +%s)) / 3600 + 2 ))
    RC_EXTRA=(-v "$WORK/wal:/wal")
    rc copy "bk:$BUCKET/postgres/main/wal" /wal --max-age "${hours}h" || { JOB_ERROR="не удалось скачать WAL"; return 1; }
    RC_EXTRA=()
    log "сегментов WAL: $(find "$WORK/wal" -type f | wc -l)"

    cat >> "$WORK/data/postgresql.auto.conf" <<'EOF'
restore_command = 'if [ -f /wal/%f.gz ]; then gunzip -c /wal/%f.gz > "%p"; else cp /wal/%f "%p"; fi'
EOF
    touch "$WORK/data/recovery.signal"
    chown -R 70:70 "$WORK"
    chmod 700 "$WORK/data"

    docker run -d --name "$NAME" -v "$WORK/data:/var/lib/postgresql/data" -v "$WORK/wal:/wal:ro" \
        "$PG_IMAGE" postgres -c shared_buffers=512MB -c max_connections=200 -c ssl=off >/dev/null || { JOB_ERROR="не запустился Postgres восстановления"; return 1; }

    local i state=""
    # max_connections не меньше, чем у исходного кластера (200): иначе Postgres
    # отказывается восстанавливаться — «insufficient parameter settings».
    for i in $(seq 1 180); do
        if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != true ]; then
            JOB_ERROR="Postgres восстановления остановился: $(docker logs --tail 4 "$NAME" 2>&1 | tr '\n' ' ' | tr '"' "'" | cut -c1-300)"
            return 1
        fi
        state=$(docker exec "$NAME" psql -U muzilla -d postgres -Atc "select pg_is_in_recovery()" 2>/dev/null)
        [ "$state" = f ] && break
        sleep 5
    done
    [ "$state" = f ] || { JOB_ERROR="восстановление не завершилось за 15 минут: $(docker logs --tail 3 "$NAME" 2>&1 | tr '\n' ' ' | tr '"' "'")"; return 1; }

    local until table live got checked=""
    until=$(docker logs "$NAME" 2>&1 | grep -o 'last completed transaction was at log time [0-9: .+-]*' | tail -1 | sed 's/.*log time //')

    for table in users orders products; do
        live=$(docker exec "$LIVE" psql -U muzilla -d muzilla_main -Atc "select count(*) from $table")
        got=$(docker exec "$NAME" psql -U muzilla -d muzilla_main -Atc "select count(*) from $table")
        if [ -z "$got" ] || [ $((got * 100)) -lt $((live * 98)) ]; then
            JOB_ERROR="$table: восстановлено ${got:-0} строк, в живой базе $live"
            return 1
        fi
        checked="$checked${checked:+,}\"$table\":$got"
    done

    JOB_EXTRA="\"base\":\"$key\",\"restored_until\":\"${until:-неизвестно}\",\"counts\":{$checked}"
}

verify() {
    local code
    restore
    code=$?
    cleanup
    return $code
}

run_job pitr-main verify
