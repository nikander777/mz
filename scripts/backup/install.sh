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
# начинаются с 01:30, а проверка на VM-2 — через час после дампа.

set -euo pipefail

ROLE=${1:-}
DIR=/opt/muzilla/scripts/backup
CRON=/etc/cron.d/muzilla-backup

case "$ROLE" in
    vm3)
        JOBS="30 1 * * * root flock -n /run/mzb-pg-main.lock $DIR/pg-offsite.sh main
30 2 * * 0 root flock -n /run/mzb-pg-discogs.lock $DIR/pg-offsite.sh discogs
40 3 * * * root $DIR/env-offsite.sh"
        ;;
    vm2)
        JOBS="30 2 * * * root flock -n /run/mzb-verify-main.lock $DIR/verify-offsite.sh main
0 6 * * 0 root flock -n /run/mzb-verify-discogs.lock $DIR/verify-offsite.sh discogs
0 4 * * * root flock -n /run/mzb-files.lock $DIR/files-offsite.sh
40 3 * * * root $DIR/env-offsite.sh"
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
