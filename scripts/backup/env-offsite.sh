#!/bin/bash
#
# Зашифрованная внешняя копия /opt/muzilla/.env этой машины → mz-backup/secrets/<vm>/.
#
# В .env — ключи платёжного агрегатора, СДЭК, S3, пароли БД: без них прод не
# поднять, а собирать их заново по кабинетам — дни. Три файла (по одному на VM)
# ведутся руками и различаются, поэтому копия снимается с каждой машины.
#
# Шифрование — rclone crypt паролем BACKUP_ENV_PASSPHRASE из .env.backup.
# Копия пароля должна лежать ВНЕ серверов (менеджер паролей): иначе при потере
# машин копии .env не расшифровать. Имена файлов не шифруются, чтобы при
# восстановлении было видно, где какая дата.
#
# Восстановление (на любой машине с .env.backup):
#   OBS=$(echo "$BACKUP_ENV_PASSPHRASE" | docker run --rm -i rclone/rclone:1.68 obscure -)
#   docker run --rm --env-file .env.backup -e RCLONE_CONFIG_BKC_TYPE=crypt \
#     -e RCLONE_CONFIG_BKC_REMOTE=bk:mz-backup/secrets -e RCLONE_CONFIG_BKC_PASSWORD="$OBS" \
#     -e RCLONE_CONFIG_BKC_FILENAME_ENCRYPTION=off -e RCLONE_CONFIG_BKC_DIRECTORY_NAME_ENCRYPTION=false \
#     rclone/rclone:1.68 cat bkc:vm1/env-YYYYMMDD-HHMMSS
#
# Запуск: cron на каждой VM, см. install.sh.

JOB="env-${BACKUP_HOST_TAG:-host}"
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
JOB="env-$HOST_TAG"

backup_env() {
    [ -n "${BACKUP_ENV_PASSPHRASE:-}" ] || { JOB_ERROR="не задан BACKUP_ENV_PASSPHRASE"; return 1; }
    [ -r /opt/muzilla/.env ] || { JOB_ERROR="нет /opt/muzilla/.env"; return 1; }

    local obscured
    obscured=$(echo "$BACKUP_ENV_PASSPHRASE" | docker run --rm -i "$RCLONE_IMAGE" obscure -) || return 1
    RC_EXTRA=(
        -e RCLONE_CONFIG_BKC_TYPE=crypt
        -e "RCLONE_CONFIG_BKC_REMOTE=bk:$BUCKET/secrets"
        -e "RCLONE_CONFIG_BKC_PASSWORD=$obscured"
        -e RCLONE_CONFIG_BKC_FILENAME_ENCRYPTION=off
        -e RCLONE_CONFIG_BKC_DIRECTORY_NAME_ENCRYPTION=false
    )

    local ts key
    ts=$(date -u +%Y%m%d-%H%M%S)
    key="$HOST_TAG/env-$ts"
    if ! rc rcat "bkc:$key" < /opt/muzilla/.env; then
        JOB_ERROR="не удалось выгрузить .env"
        return 1
    fi

    # Проверка: расшифровывается и совпадает с оригиналом.
    if ! rc cat "bkc:$key" | cmp -s - /opt/muzilla/.env; then
        JOB_ERROR="выгруженная копия .env не совпала с оригиналом при расшифровке"
        return 1
    fi

    RC_EXTRA=()
    rc delete --min-age 30d "bk:$BUCKET/secrets/$HOST_TAG"
    JOB_EXTRA="\"key\":\"secrets/$key\""
}

run_job "env-$HOST_TAG" backup_env
