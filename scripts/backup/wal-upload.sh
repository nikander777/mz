#!/bin/bash
#
# Непрерывный архив WAL кластера main → mz-backup/postgres/main/wal/ (VM-3, cron раз в минуту).
#
# WAL (журнал изменений) принимает контейнер wal-archiver-main: pg_receivewal
# через слот репликации mz_main_archive пишет сжатые сегменты в
# /opt/muzilla/backups/wal-main-spool. Этот скрипт:
#   1) раз в 5 минут закрывает текущий сегмент (pg_switch_wal) — иначе при
#      тихой ночной нагрузке 16-мегабайтный сегмент заполнялся бы часами, и
#      столько же данных было бы под угрозой. Postgres ничего не делает, если
#      с прошлого переключения записей не было;
#   2) переносит готовые сегменты в бакет (незаконченный *.partial остаётся);
#   3) проверяет, что слот активен, то есть архиватор жив.
#
# Потеря данных при аварии VM-3 — до 5 минут. Восстановление на любой момент:
# базовая копия (pg-basebackup.sh) + эти сегменты, см. docs/deployment/backups.md.
#
# Статус status/wal-main.json пишется каждый прогон: backups:check поднимет
# тревогу, если архив перестал обновляться.

JOB=wal-main
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SPOOL=/opt/muzilla/backups/wal-main-spool
PG=muzilla-postgres-main-1

pg_q() { docker exec "$PG" psql -U muzilla -d postgres -Atqc "$1"; }

upload_wal() {
    local active
    active=$(pg_q "select active from pg_replication_slots where slot_name = 'mz_main_archive'")
    if [ "$active" != t ]; then
        JOB_ERROR="слот mz_main_archive не активен — архиватор WAL (wal-archiver-main) не работает"
        return 1
    fi

    if [ $(($(date +%-M) % 5)) -eq 0 ]; then
        pg_q "select pg_switch_wal()" >/dev/null
        sleep 3
    fi

    local ready
    ready=$(find "$SPOOL" -maxdepth 1 -type f ! -name '*.partial' | wc -l)

    if [ "$ready" -gt 0 ]; then
        RC_EXTRA=(-v "$SPOOL:/spool")
        if ! rc move /spool "bk:$BUCKET/postgres/main/wal" --exclude "*.partial"; then
            JOB_ERROR="не удалось выгрузить сегменты WAL"
            return 1
        fi
        RC_EXTRA=()
        log "выгружено сегментов: $ready"
    fi

    JOB_EXTRA="\"uploaded\":$ready,\"lsn\":\"$(pg_q 'select pg_current_wal_lsn()')\""
}

# Без run_job: он пишет «старт» в журнал каждую минуту.
if upload_wal; then
    echo "{\"kind\":\"wal-main\",\"status\":\"ok\",\"finished_at\":\"$(date -u +%FT%TZ)\",\"host\":\"$HOST_TAG\",$JOB_EXTRA}" \
        | rc rcat "bk:$BUCKET/status/wal-main.json"
else
    write_status wal-main fail "\"error\":\"$JOB_ERROR\""
    exit 1
fi
