# Бэкапы: что, где, как восстановить

Ранбук внешних бэкапов. Составлен 29.09.2026, когда выяснилось, что все
копии лежали на том же RAID0 VM-3, что и база, а часть из них была битой.

Смежное: [`production-env.md`](production-env.md) · [`meili-releases-rebuild.md`](meili-releases-rebuild.md)

---

## Что бэкапится

Хранилище — Timeweb S3, бакет **`mz-backup`**. Реквизиты — `/opt/muzilla/.env.backup`
на каждой VM (права 600, вне git), формат переменных rclone, удалённый `bk:`.

| Что | Скрипт, где, когда (UTC) | Путь в бакете | Хранение |
|---|---|---|---|
| `muzilla_main` + роли кластера | `pg-offsite.sh main`, VM-3, ежедневно 01:30 | `postgres/main/daily/`, `postgres/globals/` | 35 дней |
| Проверка main восстановлением | `verify-offsite.sh main`, **VM-2**, ежедневно 02:30 | — | — |
| `muzilla_discogs` | `pg-offsite.sh discogs`, VM-3, вс 02:30 | `postgres/discogs/weekly/` | 5 недель |
| Проверка discogs полным чтением | `verify-offsite.sh discogs`, VM-2, вс 06:00 | — | — |
| Файлы: `muzilla-private` и `muzilla-images` кроме `discogs/` | `files-offsite.sh`, VM-2, ежедневно 04:00 | `files/<бакет>/` | удалённое — 30 дней в `files-deleted/<дата>/` |
| `/opt/muzilla/.env` каждой VM, зашифровано | `env-offsite.sh`, VM-1/2/3, ежедневно 03:40 | `secrets/vm1..3/` | 30 дней |

Скрипты — `scripts/backup/` в репозитории mz, запускаются cron'ом прямо из
`/opt/muzilla` (обновляются с `git pull`). Установка расписания:
`scripts/backup/install.sh vm1|vm2|vm3` → `/etc/cron.d/muzilla-backup`.
Журнал — `/var/log/muzilla-backup.log` на каждой машине.

Дамп идёт **потоком прямо в бакет**, минуя диск VM-3: 28.09.2026 дамп на этом
диске оказался испорчен при записи. Проверка восстановлением — на другой
машине по той же причине.

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

- **PITR для main** (непрерывный архив WAL): включается на весь кластер, поэтому
  ставится после выноса main в отдельный кластер Postgres. До того потеря —
  до суток (ежедневный дамп).
- Ключ бакета — от всего аккаунта Timeweb: с любой VM им можно удалить и
  бэкапы. Защита — версионирование или object lock на `mz-backup`, либо ключ
  с правами только на запись.
