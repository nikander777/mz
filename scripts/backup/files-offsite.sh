#!/bin/bash
#
# Внешняя копия пользовательских файлов: бакеты muzilla-images (кроме discogs/)
# и muzilla-private → mz-backup/files/.
#
# Фото товаров, аватары, новости, документы НКО загружены людьми и нигде больше
# не хранятся. Картинки дискографии (discogs/) не копируются: они скачаны с
# discogs.com и восстановимы, а по объёму больше всего остального.
#
# Все бакеты в одном аккаунте Timeweb, поэтому копирование идёт серверными
# командами хранилища — через машину данные не прокачиваются (фото товаров —
# 1,38 ТБ). Сравнение по контрольной сумме из листинга (--checksum), без HEAD
# на каждый из ~1 млн объектов.
#
# Удалённое или перезаписанное в источнике не пропадает сразу: rclone переносит
# прежнюю версию в files-deleted/<дата>/, откуда её можно достать 30 дней.
# --max-delete — предохранитель: если листинг источника почему-то пуст, sync не
# вычистит копию целиком.
#
# Запуск: cron на VM-2, см. install.sh. Первый прогон — долгий (все файлы).

JOB=files-offsite
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

DATE=$(date -u +%Y%m%d)

sync_files() {
    local src
    for src in muzilla-private muzilla-images; do
        log "синхронизация $src"
        if ! rc sync "bk:$src" "bk:$BUCKET/files/$src" \
            --exclude "/discogs/**" \
            --backup-dir "bk:$BUCKET/files-deleted/$DATE/$src" \
            --checksum --fast-list --transfers 32 --checkers 32 \
            --max-delete 5000 --retries 3; then
            JOB_ERROR="rclone sync $src завершился ошибкой"
            return 1
        fi
    done

    rc delete --min-age 30d "bk:$BUCKET/files-deleted"
    rc rmdirs --leave-root "bk:$BUCKET/files-deleted"

    local objects
    objects=$(rc size --json --fast-list "bk:$BUCKET/files" | grep -o '"count":[0-9]*' | cut -d: -f2)
    JOB_EXTRA="\"objects\":${objects:-0}"
}

run_job files-offsite sync_files
