#!/bin/bash
#
# Проверка внешнего бэкапа Postgres восстановлением — на ДРУГОЙ машине (VM-2).
#
#   verify-offsite.sh main     — последний дамп main целиком восстанавливается в
#                                одноразовый Postgres; число строк ключевых
#                                таблиц сверяется с зафиксированным при дампе
#   verify-offsite.sh discogs  — последний дамп discogs читается pg_restore
#                                полностью (каждый блок распаковывается)
#
# ЗАЧЕМ. «SQL backup created successfully» в логе не значит ничего: 20–22.09.2026
# дампы main были негодными, 28.09 — битый дамп discogs, и никто этого не видел.
# Бэкап, который ни разу не восстанавливали, — не бэкап. Проверка идёт на VM-2,
# а не на VM-3, где снимался дамп: на VM-3 данные портятся при записи, и
# проверка там же могла бы с этим совпасть.
#
# Одноразовый Postgres живёт на docker-томе (не tmpfs: на VM-2 8 ГБ памяти) и
# удаляется в конце при любом исходе.
#
# Запуск: cron на VM-2, см. install.sh.

JOB="verify-${1:-?}"
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
    main | discogs) ;;
    *)
        echo "Использование: $0 main|discogs" >&2
        exit 2
        ;;
esac

STATUS_JSON=$(rc cat "bk:$BUCKET/status/pg-offsite-$1.json" 2>/dev/null)
KEY=$(echo "$STATUS_JSON" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

verify_discogs() {
    [ -n "$KEY" ] || { JOB_ERROR="нет статуса последнего дампа discogs"; return 1; }
    log "полное чтение $KEY"
    if ! rc cat "bk:$BUCKET/$KEY" | docker run --rm -i "$PG_IMAGE" pg_restore -f /dev/null; then
        JOB_ERROR="pg_restore не смог прочитать $KEY"
        return 1
    fi
    JOB_EXTRA="\"key\":\"$KEY\""
}

VERIFY_PG="mz-backup-verify-$$"

# Одноразовый Postgres убирается при любом исходе проверки. Не через trap RETURN:
# в bash он не локален и сработал бы на возврате любой вложенной функции.
verify_main() {
    local code
    restore_and_count
    code=$?
    docker rm -f "$VERIFY_PG" >/dev/null 2>&1
    docker volume rm "$VERIFY_PG" >/dev/null 2>&1
    return $code
}

restore_and_count() {
    [ -n "$KEY" ] || { JOB_ERROR="нет статуса последнего дампа main"; return 1; }

    local name="$VERIFY_PG"

    docker run -d --name "$name" -v "$name:/var/lib/postgresql/data" \
        -e POSTGRES_PASSWORD=verify -e POSTGRES_DB=verify "$PG_IMAGE" >/dev/null || {
        JOB_ERROR="не запустился одноразовый Postgres"
        return 1
    }

    local i
    for i in $(seq 1 60); do
        docker exec "$name" pg_isready -U postgres -d verify >/dev/null 2>&1 && break
        sleep 2
    done

    log "восстановление $KEY"
    if ! rc cat "bk:$BUCKET/$KEY" \
        | docker exec -i "$name" pg_restore -U postgres -d verify --no-owner --no-privileges --exit-on-error; then
        JOB_ERROR="pg_restore завершился ошибкой на $KEY"
        return 1
    fi

    local tables
    tables=$(docker exec "$name" psql -U postgres -d verify -Atc \
        "select count(*) from information_schema.tables where table_schema = 'public'")

    # Сверка строк: восстановлено не меньше 98% от посчитанного при дампе
    # (счётчики снимаются за секунды до начала дампа, заказы могли измениться).
    local pairs pair table expected actual checked=""
    pairs=$(echo "$STATUS_JSON" | grep -o '"counts":{[^}]*}' | grep -oE '"[a-z_]+":[0-9]+')
    [ -n "$pairs" ] || { JOB_ERROR="в статусе дампа нет счётчиков строк"; return 1; }

    for pair in $pairs; do
        table=$(echo "$pair" | cut -d'"' -f2)
        expected=$(echo "$pair" | cut -d: -f2)
        actual=$(docker exec "$name" psql -U postgres -d verify -Atc "select count(*) from $table")
        if [ -z "$actual" ] || [ $((actual * 100)) -lt $((expected * 98)) ]; then
            JOB_ERROR="$table: восстановлено ${actual:-0} строк, при дампе было $expected"
            return 1
        fi
        checked="$checked${checked:+,}\"$table\":$actual"
    done

    JOB_EXTRA="\"key\":\"$KEY\",\"tables\":$tables,\"counts\":{$checked}"
}

run_job "verify-$1" "verify_$1"
