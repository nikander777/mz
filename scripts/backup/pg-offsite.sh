#!/bin/bash
#
# Внешний бэкап Postgres: дамп базы потоком в S3 (mz-backup), минуя диск VM-3.
#
#   pg-offsite.sh main     — muzilla_main, ежедневно, хранение 35 дней,
#                            плюс роли кластера (pg_dumpall --globals-only)
#   pg-offsite.sh discogs  — muzilla_discogs, еженедельно, хранение 5 недель
#
# ЗАЧЕМ ТАК. Локальные дампы pgbackups лежат на том же RAID0 VM-3, что и сама
# база, — отказ любого из двух дисков уносит и то и другое. Кроме того, 28.09.2026
# дамп discogs на диске VM-3 оказался битым (CRC gzip при целом маркере
# завершения): порча возникла при записи. Поэтому поток идёт сразу в бакет, а
# проверяет его восстановлением verify-offsite.sh — объект из бакета, а не с диска.
#
# Данные failed_jobs не выгружаются: для восстановления они не нужны, а битый
# TOAST в них дважды обрывал дамп целиком (22.09 main, 29.09 discogs).
#
# В статус пишется число строк ключевых таблиц на момент дампа — по нему
# verify-offsite.sh сверяет восстановленную копию.
#
# Запуск: cron на VM-3, см. install.sh.

JOB="pg-offsite-${1:-?}"
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

PG=muzilla-postgres-1
TS=$(date -u +%Y%m%d-%H%M%S)

case "${1:-}" in
    main)
        DB=muzilla_main
        PREFIX=postgres/main/daily
        KEEP=35d
        COUNT_TABLES="users orders products"
        ;;
    discogs)
        DB=muzilla_discogs
        PREFIX=postgres/discogs/weekly
        KEEP=36d
        COUNT_TABLES="releases artists masters labels"
        ;;
    *)
        echo "Использование: $0 main|discogs" >&2
        exit 2
        ;;
esac

KEY="$PREFIX/$DB-$TS.dump"

pg_q() { docker exec "$PG" psql -U muzilla -d "$DB" -Atc "$1"; }

dump() {
    local counts="" table n
    for table in $COUNT_TABLES; do
        n=$(pg_q "select count(*) from $table") || { JOB_ERROR="не удалось посчитать $table"; return 1; }
        counts="$counts${counts:+,}\"$table\":$n"
    done

    log "дамп $DB → $KEY"
    if ! docker exec "$PG" pg_dump -U muzilla -d "$DB" -Fc -Z 3 --exclude-table-data=failed_jobs \
        | rc --s3-chunk-size 128M rcat "bk:$BUCKET/$KEY"; then
        JOB_ERROR="pg_dump или выгрузка в S3 завершились ошибкой"
        return 1
    fi

    local bytes
    bytes=$(object_bytes "bk:$BUCKET/$KEY")
    if [ "${bytes:-0}" -lt 1000000 ]; then
        JOB_ERROR="дамп подозрительно мал: ${bytes:-0} байт"
        return 1
    fi

    if [ "$1" = main ]; then
        if ! docker exec "$PG" pg_dumpall -U muzilla --globals-only \
            | rc rcat "bk:$BUCKET/postgres/globals/globals-$TS.sql"; then
            JOB_ERROR="не удалось выгрузить роли кластера"
            return 1
        fi
        rc delete --min-age "$KEEP" "bk:$BUCKET/postgres/globals"
    fi

    rc delete --min-age "$KEEP" "bk:$BUCKET/$PREFIX"

    JOB_EXTRA="\"key\":\"$KEY\",\"bytes\":$bytes,\"counts\":{$counts}"
}

run_job "pg-offsite-$1" dump "$1"
