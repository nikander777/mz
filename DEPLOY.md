# MUZILLA — Deploy & Operations

Single source of truth по продакшен-инфраструктуре MUZILLA. Документ для агентов и
людей, которые должны быстро войти в проект и сделать работу без расспросов.

> **TL;DR.** 3 VM, Caddy на VM-1 ловит SSL, Nuxt SSR + два FPM Laravel'а тоже на VM-1,
> Redis/Reverb/Queues/Schedulers на VM-2, Postgres/Meili/MinIO на VM-3 (dedicated 128GB).
> Деплой: `bash scripts/deploy/deploy.sh --vm1` (или `--all`). Образы — GHCR `latest`.
> Креды — в `/opt/muzilla/.env` на каждой VM (не в git).

---

## 1. Серверы и доступы

### IP-адреса и роли

| VM | Роль | Публичный IP | Хостинг | Ресурсы |
|----|------|--------------|---------|---------|
| **VM-1** | Edge: Caddy SSL + nginx + Nuxt SSR + Laravel FPM | `90.156.211.143` | VDS (Selectel) | 4 vCPU / 8 GB / 80 GB |
| **VM-2** | App: Redis, Reverb (WSS), все queue workers, schedulers | `85.193.81.19` | VDS (Selectel) | 4 vCPU / 8 GB / 40 GB + `/mnt/disk2` 147 GB |
| **VM-3** | Data: PostgreSQL 17, Meilisearch, MinIO, бэкапы | `92.255.105.112` | Dedicated E-2388G (Timeweb) | 128 GB RAM / 4 TB |

**Сеть:** всё через публичную сеть, между VM защита по UFW (whitelist по IP). VLAN
изначально планировался, но отказались — VM-3 dedicated в другом ДЦ. Postgres/Redis
закрыты UFW, открыты только для соседних VM.

### Домены

| Домен | Указывает на | Назначение |
|-------|--------------|------------|
| `new.muzilla.ru` | VM-1 (`90.156.211.143`) | **Прод** (Caddy → edge nginx :8080) |
| `dev.muzilla.ru` | Stage VM (`194.87.86.90`) | **Stage** (single-host, отдельный VPS) |

Caddyfile на VM-1: `/etc/caddy/Caddyfile` — `reverse_proxy 127.0.0.1:8080`. SSL от
Let's Encrypt, обновляется автоматически. Старые домены `prod.nadev.ru` (prod) и
`mzt.nadev.ru` (stage) сняты после миграции 5 мая 2026 — не используем.

### SSH

Один ключ `~/.ssh/id_rsa` на локалке открывает все три VM как `root@<IP>:22`.
Конфиг скриптов деплоя — `scripts/deploy/.env.deploy` (gitignored):

```env
VM1_HOST=90.156.211.143
VM2_HOST=85.193.81.19
VM3_HOST=92.255.105.112
SSH_USER=root
SSH_PORT=22
SSH_KEY=~/.ssh/id_rsa
```

Подключение из любой роли:

```bash
ssh -i ~/.ssh/id_rsa root@90.156.211.143  # VM-1
ssh -i ~/.ssh/id_rsa root@85.193.81.19    # VM-2
ssh -i ~/.ssh/id_rsa root@92.255.105.112  # VM-3
```

CI использует свой ключ — секрет `SSH_PRIVATE_KEY` в ops-репо `nikander777/mz`.

### Креды и секреты

Все продовые секреты живут в `/opt/muzilla/.env` на **каждой** VM (3 одинаковых файла —
синхронизируйте руками при ротации). В git его нет (gitignored), пример заглушки —
`.env.prod.example`.

Ключевые переменные (обязательные):

| Переменная | Где хранится | Назначение |
|-----------|--------------|-----------|
| `POSTGRES_PASSWORD` | `.env` на всех VM | Доступ к БД (Postgres VM-3) |
| `REDIS_PASSWORD` | `.env` на VM-1, VM-2 | Auth Redis (без него worker'ы не подключаются) |
| `MEILI_MASTER_KEY` | `.env` на всех VM | Master key Meilisearch |
| `MAIN_APP_KEY`, `DISCOGS_APP_KEY` | `.env` на VM-1, VM-2 | Laravel encryption key |
| `REVERB_APP_KEY/SECRET/ID` | `.env` на VM-1, VM-2 | WebSocket auth (Reverb) |
| `DISCOGS_API_TOKEN` | `.env` на VM-1, VM-2 | **Внутренний** Bearer для middleware `api.token` (Nuxt → discogs FPM); совпадает с `INTERNAL_API_TOKEN` |
| `DISCOGS_USER_TOKEN` | `.env` на VM-1, VM-2 | Personal access token discogs.com (для api.discogs.com) |
| `S3_MEDIA_KEY/SECRET/BUCKET/ENDPOINT` | `.env` на VM-1, VM-2 | Timeweb Object Storage для изображений |
| `NUXT_PUBLIC_YMAPS_API_KEY` | `.env` на VM-1 | Yandex Maps (build-time для Nuxt, на проде runtime override) |
| `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` | `.env` VM-3 | MinIO админ |
| `ADMIN_*` (EMAIL/PHONE/PASSWORD/...) | `.env` VM-1, VM-2 | Super Admin для seeder'а |

GitHub Secrets (ops-репо `nikander777/mz`, Settings → Secrets and variables → Actions):

- `SSH_PRIVATE_KEY` — приватный ключ для CI деплоя
- `SSH_USER` (= `root`), `SSH_PORT` (= `22`)
- `VM1_HOST`, `VM2_HOST`, `VM3_HOST` — публичные IP

В сервисных репо (`mz.main`, `mz.discogs`, `mz.nuxt`):
- `OPS_DEPLOY_TOKEN` — PAT для `repository_dispatch` после билда
- В `mz.nuxt` дополнительно build-args: `LARAVEL_URL`, `BACKEND_BASE_URL`, `DISCOGS_BASE_URL`, `REVERB_HOST/PORT/SCHEME`, `DISCOGS_API_TOKEN`, `REVERB_APP_KEY`, `NUXT_PUBLIC_YMAPS_API_KEY`

---

## 2. Сервисная топология

### VM-1 (Edge) — `compose.vm1-edge.yml`

| Сервис | Образ | Что делает |
|--------|-------|-----------|
| `edge` | `nginx:1.27-alpine` | Reverse-proxy `127.0.0.1:8080`. Caddy SSL → edge → backends. Конфиг — `docker/edge/nginx.conf`. Резолвит upstream через `resolver 127.0.0.11` + переменную в `fastcgi_pass` (важно — без этого DNS залипает после рестарта контейнеров). |
| `nuxt` | `ghcr.io/nikander777/mz-nuxt:latest` | Nuxt 3 SSR. Внутри Docker-сети ходит в `http://main-web` и `http://discogs-web`. Public-параметры (apiUrl, sanctum, reverb) переопределяются runtime через `NUXT_PUBLIC_*` env (в `nuxt.config.ts` они build-time, поэтому на проде override обязателен). |
| `main` | `ghcr.io/nikander777/mz-main:latest` | Laravel 12 main FPM (порт 9000). Volume `main_storage`. |
| `main-web` | `ghcr.io/nikander777/mz-main-web:latest` | nginx-sidecar для main FPM (порт 80, имя host `main-web`). |
| `discogs` | `ghcr.io/nikander777/mz-discogs:latest` | Laravel 12 discogs FPM. Volume `discogs_storage`. |
| `discogs-web` | `ghcr.io/nikander777/mz-discogs-web:latest` | nginx-sidecar для discogs FPM. |

`edge` extra_hosts: `reverb:${VM2_HOST}` — чтобы nginx ходил в Reverb на VM-2.

### VM-2 (App) — `compose.vm2-app.yml`

| Сервис | Образ | Команда / назначение |
|--------|-------|----------------------|
| `redis` | `redis:7-alpine` | `redis-server --requirepass $REDIS_PASSWORD --appendonly yes --maxmemory 4gb --maxmemory-policy noeviction`, port 6379, volume `redis_data`. UFW открывает только VM-1. **maxmemory 4gb обязательно** — без лимита queue распухает до 7+GB и OOM-killer убивает redis (прецедент 4 мая 2026, импорт встал). |
| `reverb` | `mz-main:latest` | `php artisan reverb:start --host=0.0.0.0 --port=8080`. Caddy/edge на VM-1 проксирует WSS трафик сюда. |
| `main-queue` | `mz-main:latest` | `queue:work --tries=3 --timeout=120`. Слушает все default очереди main. |
| `main-scheduler` | `mz-main:latest` | `schedule:work` — крон-задачи main. |
| `discogs-queue` | `mz-discogs:latest` | `queue:work --queue=image-loading-high,image-processing,image-loading,default --tries=3 --timeout=300` — **с приоритетами** (см. раздел 6). По умолчанию scaled до 4 реплик (`docker compose up -d --scale discogs-queue=4`). Volume `/mnt/disk2:/discogs-dump` — для XML-дампов. |
| `discogs-scheduler` | `mz-discogs:latest` | `schedule:work` — discogs-кроны (включая `proxies:reset-flags hourly`). |

> **Память VM-2 (8 GB)** очень тесная. Текущая конфигурация (4 discogs-queue + main-queue +
> main-scheduler + reverb + redis) занимает ~6.5 GB + swap. Не масштабируйте discogs-queue выше
> 4 без апгрейда — OOM-killer убьёт reverb/redis.

### VM-3 (Data) — `compose.vm3-data.yml`

| Сервис | Образ | Параметры |
|--------|-------|-----------|
| `postgres` | `postgres:17-alpine` | `shared_buffers=32GB`, `effective_cache_size=96GB`, `work_mem=64MB`, `max_connections=200`, SSL on. Volume `pg_data`. Init `docker/postgres/init.sql` создаёт две БД: `main` и `discogs` (имена в env `MAIN_DB_DATABASE`/`DISCOGS_DB_DATABASE`). |
| `meilisearch` | `getmeili/meilisearch:v1.6` | Production mode, no analytics, port 7700. Volume `meili_data`. |
| `minio` | `minio/minio:latest` | S3-совместимое хранилище (запасной канал к Timeweb S3). Порты 9000 (API) + 9001 (console). Volume `minio_data`. |
| `pgbackups` | `prodrigestivill/postgres-backup-local:17` | `@daily` cron, retention 14d/4w/6m. Volume `./backups`. |

**Postgres SSL.** На dedicated VM-3 ходим через публичную сеть → SSL обязателен. Сертификаты
лежат в `pg_data/server.{crt,key}`. Если потеряется — пересоздать `openssl req -new -x509 -days 3650 -nodes ...` и `chown 999:999`.

UFW на VM-3 открывает 5432 (Postgres), 7700 (Meili), 9000/9001 (MinIO) только для VM-1+VM-2 IP.

---

## 3. Образы и CI/CD

### Репозитории (multi-repo)

| Репо | Branch | Содержимое | CI |
|------|--------|-----------|-----|
| `nikander777/mz.main` | `master` | Laravel main + `Dockerfile` + `Dockerfile.web` | `.github/workflows/docker.yml` → GHCR + dispatch |
| `nikander777/mz.discogs` | `main` | Laravel discogs + Dockerfile'ы | `.github/workflows/docker.yml` |
| `nikander777/mz.nuxt` | `master` | Nuxt 3 SSR + Dockerfile | `.github/workflows/docker.yml` (билд с build-args!) |
| `nikander777/mz` (ops) | `main` | `compose.*.yml`, `Makefile`, `scripts/`, `DEPLOY.md` | `.github/workflows/deploy.yml` (по `repository_dispatch`) |

Локально на маке `~/Sites/mz/` — рабочая копия ops-репо. В нём же `main/`, `discogs/`,
`nuxt/` как gitignored подкаталоги — рабочие копии сервисных репо (для удобства правок).

### Образы в GHCR

Тянутся публично (без auth):

```
ghcr.io/nikander777/mz-main:latest          + mz-main-web:latest          ← из mz.main
ghcr.io/nikander777/mz-discogs:latest       + mz-discogs-web:latest       ← из mz.discogs
ghcr.io/nikander777/mz-nuxt:latest                                        ← из mz.nuxt
```

Дополнительные теги: `sha-<commit>` и `branch-<name>` для пиннинга. На проде используем
`latest` (см. `MAIN_TAG`/`DISCOGS_TAG`/`NUXT_TAG=latest` в `/opt/muzilla/.env`).

### Поток CI/CD

```
git push в сервисный репо
  → docker.yml собирает образ + пушит в GHCR (~3-7 мин)
  → repository_dispatch event с OPS_DEPLOY_TOKEN
    → mz/.github/workflows/deploy.yml
      → SSH на VM-1: git pull + docker compose pull + up -d
```

Если что-то ломается — деплоим вручную (см. раздел 4).

### Build-time нюансы (важно!)

**Nuxt** запекает в bundle build-time переменные. Это касается:
- URL backend'ов (`LARAVEL_URL`, `BACKEND_BASE_URL`, `DISCOGS_BASE_URL`)
- API токенов (`DISCOGS_API_TOKEN`, `REVERB_APP_KEY`)
- Yandex Maps key (`vue-yandex-maps` фиксирует apikey в bundle)

В CI они приходят из секретов `mz.nuxt`. На проде дополнительно делаем **runtime
override** через `NUXT_PUBLIC_*` env в `compose.vm1-edge.yml` (см. файл, строки 122-145).
Без override клиентский bundle Nuxt полетит с дефолтным `apiUrl=http://main-web` —
браузер пользователя не дойдёт.

**Laravel** собирается с `composer install --no-dev`. Faker не входит в образ →
seeder'ы упадут с `Class "Faker\Factory" not found`. Для seed нужно временно поставить
`composer require --dev fakerphp/faker --no-interaction` внутрь контейнера.

---

## 4. Деплой

### Из локалки (рабочий путь)

```bash
cd /Users/nikander/Sites/mz
bash scripts/deploy/deploy.sh --vm1   # деплой только VM-1 (FPM, nuxt)
bash scripts/deploy/deploy.sh --vm2   # деплой только VM-2 (queues, scheduler, reverb)
bash scripts/deploy/deploy.sh --vm3   # деплой только VM-3 (postgres) — почти никогда не нужно
bash scripts/deploy/deploy.sh --all   # деплой VM-3 → VM-2 → VM-1 (порядок важен)
```

Что делает скрипт по каждой VM (см. `scripts/deploy/deploy.sh`):
1. SSH в `/opt/muzilla`
2. `git pull origin main` — обновляет compose-файлы и скрипты
3. `docker compose -f compose.<vmN>.yml pull` — тянет свежие образы из GHCR
4. `docker compose -f compose.<vmN>.yml up -d` — recreate контейнеры с новым образом
5. На VM-1 дополнительно: `php artisan migrate --force` для main и discogs

### Перед деплоем — что должно быть готово

1. **Билд GHCR прошёл успешно.** Проверь в GitHub Actions:
   ```bash
   gh run list --limit 5  # любой репо: mz.main, mz.discogs, mz.nuxt
   ```
   Жди статус `completed success` для job `Build & push Docker images`.

2. **Миграции совместимы.** Если катишь миграцию, которая ломает старый код — сначала
   деплой кода, потом миграцию (или зеро-даунтайм-pattern: добавить колонку nullable,
   деплой, заполнить, второй деплой который её требует).

3. **Compose-файл закоммичен в ops-репо.** Скрипт делает `git pull` на VM-1 — если правил
   `compose.vm1-edge.yml` локально, не запушив в `nikander777/mz`, изменения не доедут.

### Откат

Если деплой сломал прод — откатываем образ на конкретный SHA:

```bash
# На VM-1:
ssh -i ~/.ssh/id_rsa root@90.156.211.143
cd /opt/muzilla
# В .env временно подменить:
echo "MAIN_TAG=sha-<good_commit>" >> .env
echo "DISCOGS_TAG=sha-<good_commit>" >> .env
docker compose -f compose.vm1-edge.yml pull main main-web discogs discogs-web
docker compose -f compose.vm1-edge.yml up -d
```

После фикса в коде — вернуть `*_TAG=latest` и повторить.

### Health-check

```bash
bash scripts/deploy/health-check.sh --url https://new.muzilla.ru
# Проверяет:
#   /            → 200 (Nuxt SSR)
#   /health      → 200 (edge nginx)
#   /api/auth/me → 401 при Accept: application/json
#   /sanctum/csrf-cookie → 204
```

---

## 5. Очереди и фоновые задачи

### Архитектура

Redis на VM-2 — единственный broker. Workers на VM-2:

- **`main-queue`** (1 контейнер) — `default` очередь main: SMS, оплаты, мейлинг.
- **`discogs-queue`** (4 реплики) — discogs очереди **с приоритетами**:
  1. `image-loading-high` — lazy-load по факту просмотра карточки (юзер ждёт картинку)
  2. `image-processing` — постпроцессинг (resize, webp)
  3. `image-loading` — массовая загрузка обложек при импорте (фон)
  4. `default` — всё остальное

### Discogs scheduler

`discogs-scheduler` (отдельный контейнер) запускает `schedule:work`. Текущие задачи в
`discogs/routes/console.php`:

- `proxies:reset-flags` — каждый час, `withoutOverlapping`. Сбрасывает временно выключенные
  прокси обратно в `is_working=true` (см. раздел 7).

### Polling/мониторинг

```bash
# На VM-2 — глубина очередей:
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  redis-cli -h redis -a "$REDIS_PASSWORD" llen queues:image-loading-high
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  redis-cli -h redis -a "$REDIS_PASSWORD" llen queues:image-loading

# Логи workers (живые):
docker compose -f compose.vm2-app.yml logs -f --tail=50 discogs-queue

# Failed jobs:
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  php artisan queue:failed
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  php artisan queue:retry all
```

---

## 6. Image pipeline (S3, lazy-load, прокси)

### Хранилище — Timeweb Object Storage

S3-совместимое, эндпоинт `https://s3.twcstorage.ru`, бакет `muzilla-images` (регион
`ru-1`). Доступ по ключам `S3_MEDIA_KEY` / `S3_MEDIA_SECRET` (живут в `/opt/muzilla/.env`
на VM-1 и VM-2).

Структура внутри бакета:

```
muzilla-images/
  discogs/
    r{releaseId}/_catalog.webp     # catalog thumbnail (200x200)
    r{releaseId}/{filename}.webp   # full size (resized по запросу)
    a{artistId}/...
    l{labelId}/...
```

**S3-переменные критичны на VM-2** (там discogs-queue реально пишет файлы) и **на VM-1**
(там FPM генерирует URL'ы в API ответах). Если расходятся — на одной VM картинки пишутся,
на другой URL'ы кривые.

Проверка записи:

```bash
aws --endpoint-url=https://s3.twcstorage.ru s3 ls s3://muzilla-images/discogs/ --recursive | head
```

### Lazy-load механизм (важно для понимания)

Дискография — 19M release + ~9M artist + ~2M label. Загружать все картинки заранее не
вариант (Discogs API rate-limited, ~25 req/min/IP). Поэтому:

1. **При импорте XML** — flag `has_thumb=false` для всех (картинок нет, только метаданные).
2. **При первом заходе пользователя** на `/disco/release/X` (или artist/label/master) —
   `*Controller@show()` проверяет `has_thumb`. Если нет — диспатчит `LoadEntityImages` в
   `image-loading-high`, сбрасывая `images_loaded=false` (даже если флаг был залипшим).
3. **Worker качает с api.discogs.com** через ротируемый прокси-пул. Скачивает только
   primary image, ресайзит в catalog thumbnail (200x200), грузит в S3. Ставит
   `has_thumb=true`, `images_loaded=true`.
4. **При просмотре деталки полноразмерное** изображение качается через `LoadFullReleaseImages`
   уже после того, как primary выложен.

**Залипший флаг — главная ловушка.** До commit `b326664` `LoadEntityImages.markAsNoImages`
вызывался даже на 429 → `images_loaded=true` ставился навсегда → entity больше не
обходилась. Сейчас:

- При `apiData=null` (rate-limit, network, нет рабочих прокси) — `throw RuntimeException` →
  Laravel retry'ит, флаг **не** ставится.
- В `*Controller@show` проверяем `has_thumb` (фактическое наличие S3-файла), не
  `images_loaded` — на случай если флаг залип. И сбрасываем `images_loaded=false` на
  лету, чтобы worker точно перепокатился.

### Прокси-пул

DiscogsApiService ходит через прокси (таблица `proxy_servers`, ~20 анонимных). Колонки:
- `is_active` — глобально включён в ротацию
- `is_working` — последний запрос прошёл успешно
- `error_count`, `last_error` — диагностика

При фейле прокси помечается `is_working=false`. Если все 20 выключены → `No working proxy
available` → fallback на user-token discogs.com (~25 req/min, ловит 429 быстро).

**Авто-восстановление**: команда `proxies:reset-flags` (`app/Console/Commands/ResetWorkingProxies.php`)
сбрасывает `is_working=true, error_count=0` для всех `is_active=true`. Запускается
hourly через `discogs-scheduler`. Можно дёрнуть руками:

```bash
ssh -i ~/.ssh/id_rsa root@85.193.81.19 \
  'cd /opt/muzilla && docker compose -f compose.vm2-app.yml exec -T discogs-queue \
   php artisan proxies:reset-flags'
```

### Bulk-сброс залипших флагов

Если массово видишь карточки без обложек и `has_thumb=false, images_loaded=true` — нужно
сбросить флаг, чтобы при заходе/полинге снова дёрнулся job:

```bash
ssh -i ~/.ssh/id_rsa root@90.156.211.143 \
  "cd /opt/muzilla && docker compose -f compose.vm1-edge.yml exec -T discogs \
   php artisan tinker --execute='echo App\\Models\\Release::where(\"images_loaded\", true)->where(\"has_thumb\", false)->update([\"images_loaded\" => false, \"images_loaded_at\" => null]);'"
```

То же для `Artist`, `Label`. Но обычно это не нужно — `*Controller@show()` сам сбрасывает.

---

## 7. Discogs импорт (XML дампы)

### Где лежат файлы

На VM-2, `/mnt/disk2` (примонтирован в discogs-queue как `/discogs-dump`):

```
/mnt/disk2/
  discogs_20260401_releases.xml.gz       # ~11 GB gzip оригинал
  discogs_20260401_releases.xml          # ~57 GB распакованный
  discogs_20260401_releases_part1.xml    # split на 4 части для параллели
  discogs_20260401_releases_part2.xml
  discogs_20260401_releases_part3.xml
  discogs_20260401_releases_part4.xml
  discogs_20260401_artists.xml
  discogs_20260401_labels.xml
  discogs_20260401_masters.xml
```

> **Внимание: диск 147 GB, занято 130 GB.** После импорта удали `.xml` и part'ы, оставь
> только `.xml.gz` (или вообще удали — Discogs выкатывает дампы каждый месяц).

### Команды

```bash
# Войти в любой discogs-queue контейнер на VM-2:
ssh -i ~/.ssh/id_rsa root@85.193.81.19
cd /opt/muzilla

# Разбить релизы на 4 части для параллельного импорта:
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  php artisan discogs:split-xml release \
    --file=/discogs-dump/discogs_20260401_releases.xml \
    --parts=4 \
    --out=/discogs-dump

# Запустить 4 параллельных импорта (каждый в свою реплику):
for i in 1 2 3 4; do
  docker compose -f compose.vm2-app.yml exec --index=$i -d -T discogs-queue \
    php artisan import:xml release --no-images \
      --file=/discogs-dump/discogs_20260401_releases_part${i}.xml
done

# Прогресс импорта (количество release в БД):
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  php artisan tinker --execute='echo App\Models\Release::count();'

# Импорт artists / labels / masters (одиночные потоки, они меньше):
docker compose -f compose.vm2-app.yml exec -T discogs-queue \
  php artisan import:xml artist --no-images \
    --file=/discogs-dump/discogs_20260401_artists.xml
```

`--no-images` — обязательно для массового импорта. Картинки потом догружаются lazy
(см. раздел 6) или фоновым sweeper'ом.

### Скорость

После bulk-insert refactor (`XmlImportService`):
- Single thread: ~280 release/sec
- 4 параллели на VM-2: ~600-800 release/sec
- 19M release: 7-10 часов параллельно

Ограничение — Postgres concurrent writers и сетевая latency VM-2 → VM-3.

---

## 8. Каталог админских операций

### Миграции

```bash
# VM-1, main:
ssh -i ~/.ssh/id_rsa root@90.156.211.143 \
  'cd /opt/muzilla && docker compose -f compose.vm1-edge.yml exec -T main php artisan migrate --force'

# VM-1, discogs:
ssh -i ~/.ssh/id_rsa root@90.156.211.143 \
  'cd /opt/muzilla && docker compose -f compose.vm1-edge.yml exec -T discogs php artisan migrate --force'

# Откатить последнюю миграцию (только если очень нужно — обычно forward-only):
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan migrate:rollback --step=1 --force
```

Миграции для дискографии используем с `CONCURRENTLY` индексами — запускаются в отдельной
транзакции (см. примеры `2026_05_05_000000_add_has_thumb_indexes.php`).

### Очистка кэшей

```bash
# config/route/view cache (на каждом контейнере отдельно):
docker compose -f compose.vm1-edge.yml exec -T main php artisan optimize:clear
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan optimize:clear

# Application cache (Redis store) — выкинет всё:
docker compose -f compose.vm1-edge.yml exec -T discogs php artisan cache:clear
```

### Tinker

```bash
docker compose -f compose.vm1-edge.yml exec -T discogs \
  php artisan tinker --execute='echo App\Models\Release::count();'
```

Для интерактивной сессии — без `-T`.

### Просмотр логов

```bash
# Live tail контейнера:
docker compose -f compose.vm2-app.yml logs -f --tail=100 discogs-queue

# Filter по словам (быстрый way в bash):
docker compose -f compose.vm2-app.yml logs --since=10m discogs-queue 2>&1 \
  | grep -E "ERROR|WARNING|HTTP 429"
```

Laravel пишет в stderr (`LOG_CHANNEL=stderr`) → docker log = laravel log.

### Бэкапы Postgres

`pgbackups` контейнер на VM-3 делает `@daily` дамп в `/opt/muzilla/backups/`. Восстановление:

```bash
# На VM-3:
ssh -i ~/.ssh/id_rsa root@92.255.105.112
cd /opt/muzilla/backups/daily
ls *.sql.gz | tail -5
# Restore main DB:
gunzip -c muzilla-main-$(date +%Y-%m-%d).sql.gz | \
  docker compose -f /opt/muzilla/compose.vm3-data.yml exec -T postgres \
  psql -U muzilla -d main
```

### Seed demo / админ-аккаунт

```bash
# Поставить Faker в живой контейнер (нужен для seeder):
docker compose -f compose.vm1-edge.yml exec -T main \
  composer require --dev fakerphp/faker --no-interaction
docker compose -f compose.vm1-edge.yml exec -T main \
  php artisan db:seed --class=ProductionSeeder --force
```

Демо-аккаунты после `--class=DemoUserSeeder`:

| Email | Пароль | Роль |
|-------|--------|------|
| `admin@muzilla.ru` | `password` | super-admin |
| `test@example.com` | `password123` | buyer |
| `alex@musicstore.com` | `password123` | seller |
| `info@musicmarket.ru` | `store123` | store |

---

## 9. Troubleshooting

| Симптом | Причина | Решение |
|---------|---------|---------|
| Картинки не догружаются на карточке | Залипший `images_loaded=true` при `has_thumb=false`, или нет рабочих прокси | Запустить `proxies:reset-flags`. Если всё равно — bulk-сброс `images_loaded=false` (раздел 6). |
| `No working proxy available` массово в логах | Все 20 прокси упали | `php artisan proxies:reset-flags`. Если повторяется — прокси-провайдер сломался, нужно искать новые. |
| `discogs-queue` рестартует в loop | Redis перезапустился, worker не успел переподключиться. Или `REDIS_PASSWORD` не совпадает в `.env`. | Подождать 30 сек (auto-restart). Если не — проверить `REDIS_PASSWORD` в `/opt/muzilla/.env` на VM-1 и VM-2 (должен совпадать). |
| `LOADING Redis is loading the dataset in memory` в логах workers | Redis после OOM грузит AOF из persistence (1-3 минуты для большого dump'а) | Подождать. Параллельно проверить причину OOM: `dmesg \| grep -i oom`. Чаще всего — image-loading queue >7M jobs (см. ниже). |
| Redis съедает >4 GB и упирается в OOM | Распухла очередь `laravel_database_queues:image-loading` до миллионов jobs | `redis-cli -a $PASS DEL laravel_database_queues:image-loading` (массовый image-импорт уже не нужен — lazy-load по show() работает). После этого `BGREWRITEAOF` чтобы AOF не разросся. |
| `discogs:import xml release` упал на половине файла | OOM redis убил → workers умерли → детачнутые `docker exec -d` процессы импорта тоже | Перезапустить с того же part-файла — `Release::upsert` идемпотентен, дубликатов не будет. Запускать **только с `--no-images`**. |
| Edge `502 Connection refused` | nginx закэшировал старый IP upstream после recreate FPM | `docker compose -f compose.vm1-edge.yml restart edge`. (Долгосрочный фикс уже в `nginx.conf` — `resolver 127.0.0.11` + переменная.) |
| Nuxt 504 при загрузке `/disco/releases` | Не закэшированный `GROUP BY` на 19M записей | `Cache::remember('release-filter-options', 600, ...)` уже добавлен в `StatsController`. Проверь что Redis жив. |
| Nuxt: client использует `http://main-web` | Build-time URL запекся в bundle, runtime override не приехал | Проверь `NUXT_PUBLIC_API_URL` / `NUXT_PUBLIC_SANCTUM_BASE_URL` в `compose.vm1-edge.yml`. Recreate `nuxt`. |
| `password authentication failed for user "muzilla"` (Postgres) | `POSTGRES_PASSWORD` в `.env` на VM-1/VM-2 расходится с volume на VM-3 | Если volume первичный — пересоздать пароль: `docker compose -f compose.vm3-data.yml exec postgres psql -U muzilla -c "ALTER USER muzilla PASSWORD '...';"`. |
| `Class "Faker\Factory" not found` при seed | Образ собран `--no-dev` | `composer require --dev fakerphp/faker --no-interaction` внутри контейнера. |
| `varchar(255)` overflow при импорте discogs | У некоторых ролей в Discogs длина >255 символов | Применена миграция `widen_text_columns_for_discogs`. Если ловишь повторно — проверь схему `releases.role`/`tracklists.title`. |
| Deadlock при параллельном импорте | Postgres deadlock на parallel inserts (40P01) | В `XmlImportService` уже есть retry на 40P01 + ksort stub IDs. Если ловится массово — снизь parallel count до 2. |
| Очередь `image-loading` распухла на 9M | Это нормально для discogs импорта | Ждать или поднять `--scale=8` workers (если хватает RAM на VM-2; обычно нет — лучше 4). |
| `/mnt/disk2` забит на 95% | XML дампы и part-файлы | Удалить `.xml` и `part_*.xml` после импорта. Оставить только `.xml.gz` (или вообще удалить). |

---

## 10. Stage / dev окружения

### Stage (single-host)

`compose.stage.yml` запускает **всё** в одной машине: postgres + redis + reverb + meili +
nuxt + main + discogs + edge. Используется для smoke-теста перед prod.

```bash
cd /Users/nikander/Sites/mz
cp .env.prod.example .env
# Сгенерировать секреты:
echo "POSTGRES_PASSWORD=$(openssl rand -hex 32)" >> .env
echo "MEILI_MASTER_KEY=$(openssl rand -hex 32)" >> .env
# ...и т.д.
make build
make up
make migrate
make seed-demo
bash scripts/deploy/health-check.sh --url http://localhost
```

Полный гайд по stage — в этом же файле, исторический раздел в git history.

### Локальная разработка

`docker-compose.yml` (без префиксов). Запускается через `composer run dev` в `main/` —
этот скрипт стартует Laravel + queue + Vite параллельно на хосте, без Docker.

Тесты:

| Сервис | Порт |
|--------|------|
| `main` Laravel | `php artisan serve` → :8000 |
| `discogs` Laravel | `php artisan serve --port=8001` → :8001 |
| `main` Reverb | `php artisan reverb:start` → :8080 |
| `nuxt` | `npm run dev` → :3000 |

> Эти сервера у разработчика **запущены постоянно**. Не запускай свои на тех же портах.

---

## 11. Make-shortcuts

```bash
make help                        # справка по всем целям

# Stage:
make build / up / down / logs    # сборка / запуск / останов / логи
make migrate                     # миграции main + discogs
make seed-demo                   # demo-аккаунты + товары
make pull / deploy               # pull из GHCR / pull + up

# Prod (запускать на нужной VM по SSH):
make vm1 / vm2 / vm3             # pull + up -d
make vm1-logs / vm2-logs / vm3-logs

# Деплой из локалки:
make deploy-all                  # SSH-deploy на все VM
make deploy-vm1 / vm2 / vm3      # точечно

# Провижининг (один раз на новой VM):
make provision-vm1 / vm2 / vm3

# Мониторинг:
make health
```

---

## 12. Архивные нюансы

### Миграция временного VM-3 → dedicated

Сделана в апреле 2026. Тогда VM-3 поднималась на VPS, потом данные перенесены
`pg_dumpall | psql` на dedicated E-2388G, `VM3_HOST` обновлён в `.env` всех VM.

### Переход доменов на muzilla.ru (5 мая 2026)

Совершён ровно так:

1. Caddyfile (VM-1, stage VM): добавлен блок нового домена + временный 301-редирект
   со старого. Через сутки 301-редиректы сняты, старые домены `prod.nadev.ru`/`mzt.nadev.ru`
   больше не отвечают.
2. `/opt/muzilla/.env`: `sed -i 's/<old>/<new>/g'` на VM-1, VM-2 и stage. Обновлены
   `PUBLIC_HOST`, `MAIN_APP_URL`, `DISCOGS_APP_URL`, `REVERB_HOST`,
   `NUXT_BACKEND_BASE_URL`, `SANCTUM_STATEFUL_DOMAINS`, `SESSION_DOMAIN`.
3. `docker compose up -d --force-recreate nuxt main main-web discogs discogs-web`
   на VM-1, и `reverb main-queue main-scheduler discogs-queue discogs-scheduler` на
   VM-2.
4. **Обязательно** `php artisan optimize:clear` для main и discogs FPM — иначе
   `bootstrap/cache/config.php` держит старый домен и `/sanctum/csrf-cookie` падает 500.
5. `mz.nuxt` GitHub Variables (`BACKEND_BASE_URL`, `REVERB_HOST`) тоже обновлены под
   prod-домен — это build-time дефолт для CI-сборки Nuxt-bundle.

При следующей смене домена — повторить тот же чек-лист.

---

## 13. Контакты и зоны ответственности

- **Инфраструктура / деплой** — `nikander@me.com`
- **GitHub Actions / GHCR** — нужен `OPS_DEPLOY_TOKEN` PAT, лежит в Bitwarden (?)
- **Timeweb Cloud (S3, VM-3 dedicated)** — там же
- **Selectel (VM-1, VM-2)** — там же

При утрате доступов — Caddy сам обновит SSL, Postgres сам идёт, prod не упадёт. Самое
рискованное — потеря `POSTGRES_PASSWORD` или `MAIN_APP_KEY`/`DISCOGS_APP_KEY`. Они есть
в `/opt/muzilla/.env` на VM, но если все VM убитые одновременно — копий нет.
