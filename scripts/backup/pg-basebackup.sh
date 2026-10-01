#!/bin/bash
#
# Базовая копия кластера main (pg_basebackup) → mz-backup/postgres/main/base/ (VM-3, ежедневно).
#
# Вместе с архивом WAL (wal-upload.sh) даёт восстановление на любой момент
# времени: берётся последняя базовая копия до нужного момента и к ней
# проигрываются сегменты WAL. Копия без WAL внутри (-X none) — WAL берётся из
# архива; поэтому сегменты хранятся на сутки дольше самой старой копии.
#
# Поток идёт прямо в бакет, минуя диск VM-3. Хранение — 8 дней.
# Проверка восстановлением — verify-pitr.sh.

JOB=base-main
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

PG=muzilla-postgres-main-1
TS=$(date -u +%Y%m%d-%H%M%S)
KEY="postgres/main/base/base-$TS.tar.gz"

basebackup() {
    log "базовая копия → $KEY"
    if ! docker exec "$PG" pg_basebackup -U muzilla -D - -Ft -X none -z -c fast --label "mz-base-$TS" \
        | rc --s3-chunk-size 64M rcat "bk:$BUCKET/$KEY"; then
        JOB_ERROR="pg_basebackup или выгрузка в S3 завершились ошибкой"
        return 1
    fi

    local bytes
    bytes=$(object_bytes "bk:$BUCKET/$KEY")
    if [ "${bytes:-0}" -lt 10000000 ]; then
        JOB_ERROR="базовая копия подозрительно мала: ${bytes:-0} байт"
        return 1
    fi

    rc delete --min-age 8d "bk:$BUCKET/postgres/main/base"
    rc delete --min-age 9d "bk:$BUCKET/postgres/main/wal"

    JOB_EXTRA="\"key\":\"$KEY\",\"bytes\":$bytes,\"started_at\":\"$(date -u -d "${TS:0:8} ${TS:9:2}:${TS:11:2}:${TS:13:2}" +%FT%TZ)\""
}

run_job base-main basebackup
