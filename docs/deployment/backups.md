# Бэкапы: что, где, как восстановить

Ранбук внешних бэкапов. Составлен 29.09.2026, когда выяснилось, что все
копии лежали на том же RAID0 VM-3, что и база, а часть из них была битой.

Смежное: [`production-env.md`](production-env.md) · [`meili-releases-rebuild.md`](meili-releases-rebuild.md)

---

## Раскладка данных (с 01.10.2026)

| Что | Где | Порт на VM-3 |
|---|---|---|
| `muzilla_main` | контейнер `postgres-main` (отдельный кластер, `data_checksums`) | 5433 |
| `muzilla_discogs` | контейнер `postgres` (общий прежний кластер) | 5432 |
| Meili main: `products`, `sellers` | `meilisearch-main` | 7701 |
| Meili дискографии: `releases`, `artists`, `masters`, `labels` | `meilisearch` | 7700 |

Сервисы main берут порт базы из `MAIN_DB_PORT`, адрес Meili — из
`MAIN_MEILISEARCH_HOST` (в `.env` VM-1/VM-2); глобальный поиск ищет по
дискографии через `DISCO_MEILISEARCH_HOST`. Порты данных VM-3 открыты только
для VM-1 и VM-2 (`scripts/deploy/vm3-data-guard.sh`), с ноутбука — через
`ssh -N -L 15433:localhost:5433 root@92.255.105.112`.

Старая копия main в общем кластере — `muzilla_main_old_20261001` (путь отката,
удалить после 08.10.2026).

## Что бэкапится

Хранилище — Timeweb S3, бакет **`mz-backup`**. Реквизиты — `/opt/muzilla/.env.backup`
на каждой VM (права 600, вне git), формат переменных rclone, удалённый `bk:`.

| Что | Скрипт, где, когда (UTC) | Путь в бакете | Хранение |
|---|---|---|---|
| `muzilla_main` + роли кластера | `pg-offsite.sh main`, VM-3, ежедневно 01:30 | `postgres/main/daily/`, `postgres/globals/` | 35 дней |
| Проверка main восстановлением | `verify-offsite.sh main`, VM-3, ежедневно 02:00 | — | — |
| **Архив WAL main** (восстановление на любой момент, потеря ≤ 5 мин) | контейнер `wal-archiver-main` + `wal-upload.sh`, VM-3, раз в минуту | `postgres/main/wal/` | 9 дней |
| Базовая копия кластера main | `pg-basebackup.sh`, VM-3, ежедневно 01:45 | `postgres/main/base/` | 8 дней |
| Проверка восстановления на момент времени | `verify-pitr.sh`, VM-3, ежедневно 02:15 | — | — |
| `muzilla_discogs` | `pg-offsite.sh discogs`, VM-3, вс 02:30 | `postgres/discogs/weekly/` | 5 недель |
| Проверка discogs полным чтением | `verify-offsite.sh discogs`, VM-3, вс 04:30 | — | — |
| Файлы: `muzilla-private` и `muzilla-images` кроме `discogs/` | `files-offsite.sh`, VM-3, ежедневно 04:00 | `files/<бакет>/` | удалённое — 30 дней в `files-deleted/<дата>/` |
| `/opt/muzilla/.env` каждой VM, зашифровано | `env-offsite.sh`, VM-1/2/3, ежедневно 03:40 | `secrets/vm1..3/` | 30 дней |

Скрипты — `scripts/backup/` в репозитории mz, запускаются cron'ом прямо из
`/opt/muzilla` (обновляются с `git pull`). Установка расписания:
`scripts/backup/install.sh vm1|vm2|vm3` → `/etc/cron.d/muzilla-backup`.
Журнал — `/var/log/muzilla-backup.log` на каждой машине.

Дамп идёт **потоком прямо в бакет**, минуя диск VM-3: 28.09.2026 дамп на этом
диске оказался испорчен при записи. Проверяется объект в бакете, поэтому
проверку можно гонять и на VM-3: сбойная память даст там только ложную
тревогу, не ложный «успех». Всё тяжёлое — на VM-3 (128 ГБ, 16 потоков);
VM-2 — обычная VDS, занятая воркерами, на ней только копия её `.env`.

Не бэкапятся: Meilisearch (производная копия Postgres, пересобирается —
см. `meili-releases-rebuild.md`), Redis (очереди и сессии), картинки дискографии
(скачаны с discogs.com, восстановимы).

Локальные ночные дампы `pgbackups` в `/opt/muzilla/backups` на VM-3 остаются —
для быстрого восстановления на месте, но это не бэкап: тот же диск.

## Контроль

Каждый прогон пишет `status/<задача>.json` (итог, время, размер, счётчики
строк). `backups:check` в main-scheduler (VM-2) раз в час проверяет, что все
статусы есть, успешны и свежие, и шлёт письмо на `BACKUP_ALERT_EMAIL`
(по умолчанию `PROXY_ALERT_EMAIL`, затем `ADMIN_EMAIL`). Нормы свежести —
`main/config/backups.php`. Устаревший статус означает, что скрипт перестал
запускаться, — это тоже алерт.

Руками: `docker exec muzilla-main-scheduler-1 php artisan backups:check`.

## Восстановление

Везде ниже `R="docker run --rm -i --env-file /opt/muzilla/.env.backup rclone/rclone:1.68"`.

### main

```bash
$R lsf bk:mz-backup/postgres/main/daily/ | tail -3        # выбрать дамп
$R cat bk:mz-backup/postgres/globals/globals-<ts>.sql \
  | docker exec -i muzilla-postgres-1 psql -U muzilla -d postgres   # роли, если кластер новый
docker exec muzilla-postgres-1 createdb -U muzilla muzilla_main_restore
$R cat bk:mz-backup/postgres/main/daily/<файл>.dump \
  | docker exec -i muzilla-postgres-1 pg_restore -U muzilla -d muzilla_main_restore --no-owner
```

Восстанавливать в новую базу рядом, сверять и только потом переключать
`MAIN_DB_DATABASE` / переименовывать. Время: ~1–2 минуты (дамп ~160 МБ).

### main на конкретный момент (PITR)

Например, вернуть базу на момент перед ошибочным `DELETE`. Берётся последняя
базовая копия **до** нужного момента и к ней проигрывается архив WAL.
Восстанавливать рядом, в отдельный контейнер; затем сверить и решить,
переносить ли данные или переключаться целиком. Так же работает ежедневная
проверка `verify-pitr.sh` — её код и есть рабочий рецепт.

```bash
W=/opt/muzilla/backups/pitr-manual && mkdir -p $W/data $W/wal
$R lsf bk:mz-backup/postgres/main/base/                      # base-<ts>.tar.gz, выбрать до нужного момента
$R cat bk:mz-backup/postgres/main/base/base-<ts>.tar.gz | tar -xz -C $W/data
$R -v $W/wal:/wal copy bk:mz-backup/postgres/main/wal /wal --max-age 48h
cat >> $W/data/postgresql.auto.conf <<'EOF'
restore_command = 'if [ -f /wal/%f.gz ]; then gunzip -c /wal/%f.gz > "%p"; else cp /wal/%f "%p"; fi'
recovery_target_time = '2026-10-01 12:34:00+00'
recovery_target_action = 'promote'
EOF
touch $W/data/recovery.signal && chown -R 70:70 $W && chmod 700 $W/data
docker run -d --name mz-pitr-manual -v $W/data:/var/lib/postgresql/data -v $W/wal:/wal:ro \
  postgres:17-alpine postgres -c max_connections=200 -c ssl=off
docker logs -f mz-pitr-manual        # ждать «database system is ready to accept connections»
```

`max_connections` — не меньше, чем у исходного кластера (200), иначе Postgres
откажется восстанавливаться. Время: базовая копия ~300 МБ, восстановление —
десятки секунд.

### discogs

То же с `postgres/discogs/weekly/`, дамп ~14 ГБ. Для параллельного
восстановления (`pg_restore -j 8`) дамп сначала скачать в файл — из потока
pg_restore параллелить не умеет.

### Файлы

```bash
$R copy bk:mz-backup/files/muzilla-images/products/<путь> bk:muzilla-images/products/<путь>
$R lsf -R bk:mz-backup/files-deleted/          # удалённое за последние 30 дней
```

Копирование серверное (один аккаунт Timeweb), через машину данные не идут.

### .env

Пароль шифрования — `BACKUP_ENV_PASSPHRASE` в `.env.backup` и **копия в
менеджере паролей владельца**: без неё при потере всех трёх машин копии не
расшифровать.

```bash
OBS=$(echo "$BACKUP_ENV_PASSPHRASE" | docker run --rm -i rclone/rclone:1.68 obscure -)
$R -e RCLONE_CONFIG_BKC_TYPE=crypt -e RCLONE_CONFIG_BKC_REMOTE=bk:mz-backup/secrets \
   -e RCLONE_CONFIG_BKC_PASSWORD="$OBS" -e RCLONE_CONFIG_BKC_FILENAME_ENCRYPTION=off \
   -e RCLONE_CONFIG_BKC_DIRECTORY_NAME_ENCRYPTION=false \
   ... cat bkc:vm1/env-<ts>
```

(`-e` для crypt добавляются в ту же команду `docker run` перед образом.)

## Что ещё не сделано

- Ключ бакета — от всего аккаунта Timeweb: с любой VM им можно удалить и
  бэкапы. Защита — версионирование или object lock на `mz-backup`, либо ключ
  с правами только на запись.
