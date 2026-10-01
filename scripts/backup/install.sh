#!/bin/bash
#
# Установка расписания внешних бэкапов на машине: install.sh vm1|vm2|vm3
#
# Кладёт /etc/cron.d/muzilla-backup и ротацию лога. Скрипты запускаются прямо из
# git-копии /opt/muzilla, так что обновляются вместе с `git pull` при деплое.
# Требует /opt/muzilla/.env.backup с реквизитами бакета, BACKUP_HOST_TAG и
# BACKUP_ENV_PASSPHRASE (см. docs/deployment/backups.md).
#
# Время — UTC. Ночные локальные дампы pgbackups идут в 00:00, поэтому внешние
# начинаются с 01:30. Всё тяжёлое (проверка восстановлением, синхронизация
# файлов) — на VM-3: там 128 ГБ памяти, 16 потоков и ночью почти нет нагрузки.
# VM-2 — обычная VDS, её CPU целиком занят воркерами очередей; на ней и на VM-1
# только копия собственного .env (секунды).

set -euo pipefail

ROLE=${1:-}
DIR=/opt/muzilla/scripts/backup
CRON=/etc/cron.d/muzilla-backup

case "$ROLE" in
    vm3)
        JOBS="30 1 * * * root flock -n /run/mzb-pg-main.lock $DIR/pg-offsite.sh main
45 1 * * * root flock -n /run/mzb-base-main.lock $DIR/pg-basebackup.sh
0 2 * * * root flock -n /run/mzb-verify-main.lock $DIR/verify-offsite.sh main
15 2 * * * root flock -n /run/mzb-pitr-main.lock $DIR/verify-pitr.sh
* * * * * root flock -n /run/mzb-wal-main.lock $DIR/wal-upload.sh
30 2 * * 0 root flock -n /run/mzb-pg-discogs.lock $DIR/pg-offsite.sh discogs
30 4 * * 0 root flock -n /run/mzb-verify-discogs.lock $DIR/verify-offsite.sh discogs
0 4 * * * root flock -n /run/mzb-files.lock $DIR/files-offsite.sh
40 3 * * * root $DIR/env-offsite.sh"
        ;;
    vm2)
        JOBS="40 3 * * * root $DIR/env-offsite.sh"
        ;;
    vm1)
        JOBS="40 3 * * * root $DIR/env-offsite.sh"
        ;;
    *)
        echo "Использование: $0 vm1|vm2|vm3" >&2
        exit 2
        ;;
esac

[ -r /opt/muzilla/.env.backup ] || { echo "Нет /opt/muzilla/.env.backup" >&2; exit 1; }
grep -q "^BACKUP_HOST_TAG=$ROLE$" /opt/muzilla/.env.backup || { echo "В .env.backup нет BACKUP_HOST_TAG=$ROLE" >&2; exit 1; }

chmod +x "$DIR"/*.sh

# На VM-3 cron не было вовсе — файл в /etc/cron.d лежал бы мёртвым грузом.
if ! systemctl is-active --quiet cron; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q cron >/dev/null
    systemctl enable --now cron
fi

cat > "$CRON" <<EOF
# Внешние бэкапы MUZILLA ($ROLE). Источник: scripts/backup/install.sh в репозитории mz.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$JOBS
EOF
chmod 644 "$CRON"

cat > /etc/logrotate.d/muzilla-backup <<'EOF'
/var/log/muzilla-backup.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
EOF

echo "Установлено: $CRON"
cat "$CRON"
