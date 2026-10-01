#!/bin/bash
#
# Общие функции внешних бэкапов (подключается из остальных скриптов каталога).
#
# Реквизиты бакета лежат в /opt/muzilla/.env.backup (права 600, вне git) в
# формате переменных rclone: удалённый `bk:` = Timeweb S3, бакет mz-backup.
# rclone запускается контейнером — ставить его на хосты не нужно.
#
# Каждая задача в конце пишет в бакет status/<задача>.json. По этим файлам
# команда `backups:check` в main раз в час проверяет, что копии свежие и
# успешные, и шлёт письмо, если нет. Файл статуса пишется и при провале, а
# если скрипт перестал запускаться вовсе — устаревает, и это тоже алерт.

set -o pipefail

BACKUP_ENV=${BACKUP_ENV:-/opt/muzilla/.env.backup}
RCLONE_IMAGE=rclone/rclone:1.68
PG_IMAGE=postgres:17-alpine
LOG=/var/log/muzilla-backup.log

if [ ! -r "$BACKUP_ENV" ]; then
    echo "Нет $BACKUP_ENV — реквизиты бакета бэкапов не настроены" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
. "$BACKUP_ENV"
set +a

BUCKET=${BACKUP_BUCKET:-mz-backup}
HOST_TAG=${BACKUP_HOST_TAG:-$(hostname -s)}
RC_EXTRA=()

# Всё, что задача пишет в stderr (pg_restore, rclone), — в журнал: cron вывод
# выбрасывает, и 30.09–01.10 ночная проверка падала без текста ошибки.
exec 2>>"$LOG"

log() { echo "$(date -u +%FT%TZ) [$JOB] $*" | tee -a "$LOG"; }

# rclone в контейнере. -i нужен, чтобы rcat читал поток из конвейера.
rc() { docker run --rm -i --env-file "$BACKUP_ENV" "${RC_EXTRA[@]}" "$RCLONE_IMAGE" -q "$@"; }

# Размер объекта в байтах (0, если объекта нет).
object_bytes() { rc size --json "$1" 2>/dev/null | grep -o '"bytes":[0-9]*' | cut -d: -f2 || echo 0; }

# status/<kind>.json: итог задачи для backups:check. $3 — дополнительные поля JSON.
write_status() {
    local body="{\"kind\":\"$1\",\"status\":\"$2\",\"finished_at\":\"$(date -u +%FT%TZ)\",\"host\":\"$HOST_TAG\"${3:+,$3}}"
    echo "$body" | rc rcat "bk:$BUCKET/status/$1.json"
    log "статус $1 = $2 ${3:-}"
}

# Выполнить функцию задачи и записать итог; при провале — статус fail и код 1.
run_job() {
    local kind=$1
    shift
    log "старт"
    local started=$SECONDS
    if "$@"; then
        write_status "$kind" ok "\"seconds\":$((SECONDS - started))${JOB_EXTRA:+,$JOB_EXTRA}"
    else
        write_status "$kind" fail "\"seconds\":$((SECONDS - started)),\"error\":\"${JOB_ERROR:-см. /var/log/muzilla-backup.log на $HOST_TAG}\""
        exit 1
    fi
}
