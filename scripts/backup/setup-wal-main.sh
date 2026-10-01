#!/bin/bash
#
# Однократная подготовка архива WAL кластера main на VM-3 (идемпотентна).
#
#   - физический слот репликации mz_main_archive: Postgres не удалит сегменты,
#     пока архиватор их не забрал;
#   - потолок удержания WAL слотом — 50 ГБ (если архиватор умрёт надолго, диск
#     не забьётся; архив при этом прервётся, и backups:check поднимет тревогу);
#   - каталог-накопитель для pg_receivewal с владельцем postgres (uid 70).
#
# Затем: docker compose -f compose.vm3-data.yml up -d --no-deps wal-archiver-main

set -euo pipefail

PG=muzilla-postgres-main-1
SPOOL=/opt/muzilla/backups/wal-main-spool

docker exec "$PG" psql -U muzilla -d postgres -v ON_ERROR_STOP=1 -Atq <<'SQL'
select pg_create_physical_replication_slot('mz_main_archive', true)
where not exists (select 1 from pg_replication_slots where slot_name = 'mz_main_archive');
alter system set max_slot_wal_keep_size = '50GB';
select pg_reload_conf();
SQL

mkdir -p "$SPOOL"
chown 70:70 "$SPOOL"
chmod 700 "$SPOOL"

docker exec "$PG" psql -U muzilla -d postgres -Atc \
    "select slot_name, active, restart_lsn, current_setting('max_slot_wal_keep_size') from pg_replication_slots"
