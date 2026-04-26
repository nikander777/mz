# MUZILLA — деплой

Инфраструктура для трёх сервисов: `main` (Laravel), `discogs` (Laravel), `nuxt` (Nuxt 3 SSR).

## Окружения

| Окружение | Файл compose | Назначение |
|-----------|--------------|-----------|
| **dev** | `docker-compose.yml` | Локальная разработка. Билдит образы на месте, edge на `:8088`. |
| **stage** | `compose.stage.yml` | Single-host deploy. Все сервисы на одной машине. Билдит локально или из GHCR. |
| **prod VM-1** | `compose.vm1-edge.yml` | Edge + Nuxt SSR + Laravel FPM sidecars. |
| **prod VM-2** | `compose.vm2-app.yml` | Redis, Reverb (WSS), очереди, scheduler. |
| **prod VM-3** | `compose.vm3-data.yml` | Postgres, Meilisearch, MinIO, бэкапы. |

## Архитектура prod (3 VM)

```
Интернет
   │
   ▼
VM-1 (VDS High CPU 4c/8GB)      ◄── mzt.nadev.ru
  Caddy (SSL) → edge nginx
  Nuxt SSR, PHP-FPM (main, discogs)
   │ VLAN           │ публичная сеть + firewall
VM-2 (VDS Premium 4c/8GB)    VM-3 (Dedicated E-2388G 128GB/4TB)
  Redis, Reverb               PostgreSQL, Meilisearch
  Queues, Scheduler            MinIO, Backups
```

**Сеть:** VM-1 ↔ VM-2 по VLAN. К VM-3 (dedicated) через публичную сеть с ufw whitelist IP + PostgreSQL SSL.

## Репозитории (multi-repo)

| Репо | Что внутри | Branch | CI |
|------|-----------|--------|----|
| `nikander777/mz.main` | Laravel main + Dockerfile + Dockerfile.web | master | `.github/workflows/docker.yml` |
| `nikander777/mz.discogs` | Laravel discogs + Dockerfile + Dockerfile.web | main | `.github/workflows/docker.yml` |
| `nikander777/mz.nuxt` | Nuxt 3 SSR + Dockerfile | master | `.github/workflows/docker.yml` |
| `nikander777/mz` (ops, новый) | compose.*.yml, Makefile, scripts/, DEPLOY.md, deploy.yml | main | `.github/workflows/deploy.yml` |

Локально на маке `~/Sites/mz/` — это рабочая копия ops-репо, а `main/`, `discogs/`, `nuxt/`
(в .gitignore) — рабочие копии сервисных репо.

## Образы (GHCR)

Пушатся автоматически каждым сервисом на push в свой main/master:

- `ghcr.io/nikander777/mz-main:latest` + `mz-main-web:latest` ← из mz.main
- `ghcr.io/nikander777/mz-discogs:latest` + `mz-discogs-web:latest` ← из mz.discogs
- `ghcr.io/nikander777/mz-nuxt:latest` ← из mz.nuxt

Теги: `latest` + `sha-<commit>` + `branch-<name>` для пиннинга.

## Особенности билда (важно!)

### Nuxt — build-time переменные

Nuxt SSR запекает в bundle при сборке:
- URL'ы backend'а (`LARAVEL_URL`, `BACKEND_BASE_URL`, `DISCOGS_BASE_URL`)
- API-токены и Reverb-параметры
- Yandex Maps API key (`vue-yandex-maps` фиксирует apikey в bundle)

Эти значения передаются:
- **Локально (stage)**: через `build.args` в `compose.stage.yml` (читается из `.env`)
- **CI (prod)**: через `build-args:` в `mz.nuxt/.github/workflows/docker.yml` — vars/secrets настраиваются в **mz.nuxt → Settings → Secrets and variables → Actions**:
  - Variables: `LARAVEL_URL`, `BACKEND_BASE_URL`, `DISCOGS_BASE_URL`, `REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`
  - Secrets: `DISCOGS_API_TOKEN`, `REVERB_APP_KEY`, `NUXT_PUBLIC_YMAPS_API_KEY`

Дефолты в `nuxt/Dockerfile` рассчитаны на single-host setup (`http://main-web`/`http://discogs-web`).
Для prod на отдельном домене — задай vars/secrets перед первым push в mz.nuxt.

Если меняешь `.env` локально — пересоберись:

```bash
docker compose -f compose.stage.yml build --pull=false nuxt
```

### Laravel — `--no-dev` в prod-образах

`mz.main/Dockerfile` и `mz.discogs/Dockerfile` собирают vendor с `--no-dev` — пакеты из
`require-dev` (включая `fakerphp/faker`) **отсутствуют в образе**. Если запустить
`php artisan db:seed`, факторы упадут с `Class "Faker\Factory" not found`. Для seed
нужно временно поставить Faker в живой контейнер:
`composer require --dev fakerphp/faker`. См. `make seed-demo`.

## CI/CD

Поток: `git push` в сервисный репо → `docker.yml` собирает образ + пушит в GHCR →
`repository_dispatch` event → `mz/.github/workflows/deploy.yml` → SSH на VM-1.

### Первичная настройка GitHub (один раз)

**1. Создать ops-репо `nikander777/mz` и запушить**:

Локально ops уже инициализирован (`git init` + 2 коммита сделаны). Осталось:

```bash
cd /Users/nikander/Sites/mz
# Создай пустой репо на github.com/new — name: mz (private или public)
git remote add origin git@github.com:nikander777/mz.git
git push -u origin main
```

**2. Запушить локальные коммиты в сервисные репо**:

В каждом сервисе сделаны коммиты с фиксами и docker.yml-патчами:

```bash
cd /Users/nikander/Sites/mz/main && git push origin master
cd /Users/nikander/Sites/mz/discogs && git push origin main
# ОСТОРОЖНО: в mz.nuxt есть твои несохранённые правки в app.vue/components.
# Закоммить или закрой их сначала, потом:
cd /Users/nikander/Sites/mz/nuxt && git push origin master
```

**3. SSH-ключ для деплоя** на локальной машине:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/muzilla_deploy -C "muzilla-ci-deploy" -N ""
# Публичный ключ — на каждую VM:
for host in <VM1_IP> <VM2_IP> <VM3_IP>; do
    ssh-copy-id -i ~/.ssh/muzilla_deploy.pub root@$host
done
```

**4. PAT для repository_dispatch (`OPS_DEPLOY_TOKEN`)**:

Создай Personal Access Token: https://github.com/settings/tokens/new?scopes=repo
Название «mz-deploy-trigger», scope `repo`. Сохрани — нужен в каждом сервисном репо.

**5. Secrets и variables по репо** (Settings → Secrets and variables → Actions):

В **`mz.main`, `mz.discogs`, `mz.nuxt`** — Secret:

- `OPS_DEPLOY_TOKEN` — PAT из п. 4

В **`mz.nuxt`** дополнительно (для build-args, см. раздел "Особенности билда"):

- Variables: `LARAVEL_URL`, `BACKEND_BASE_URL`, `DISCOGS_BASE_URL`, `REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`
- Secrets: `DISCOGS_API_TOKEN`, `REVERB_APP_KEY`, `NUXT_PUBLIC_YMAPS_API_KEY`

В **ops-репо `nikander777/mz`**:

- `SSH_PRIVATE_KEY` — содержимое `~/.ssh/muzilla_deploy` (`cat`)
- `SSH_USER` — `root`
- `SSH_PORT` — `22`
- `VM1_HOST` — публичный IP VM-1
- `VM2_HOST` — публичный IP VM-2
- `VM3_HOST` — публичный IP VM-3 (временный или dedicated)

**6. GHCR публичность**: после первой сборки появится package в GHCR как **private**.
Чтобы VM-ки тянули без `docker login`, сделай каждый public:
GitHub → твой профиль → Packages → каждый (`mz-main`, `mz-main-web`, `mz-discogs`,
`mz-discogs-web`, `mz-nuxt`) → Package settings → Change visibility → Public.

Альтернатива — оставить private и на каждой VM выполнить `docker login ghcr.io` с PAT
(scope `read:packages`); `setup_ghcr_login` в provision-скриптах это делает.

**7. Тест полного цикла**:

```bash
# В любом из сервисов — пустой коммит для триггера:
cd /Users/nikander/Sites/mz/main
git commit --allow-empty -m "ci: trigger test"
git push origin master
```

Открой `mz.main → Actions` — `Build & push Docker images` должен зеленеть на 2 jobs
(app + web) ~5-10 минут. Сразу после — в `nikander777/mz → Actions` стартанёт `Deploy`
от `repository_dispatch`. Пойдёт SSH на VM-1, сделает `git pull` ops-репо
и `docker compose pull && up -d`.

---

# Stage — локальный single-host деплой с demo-данными

Это путь, который мы прогнали и проверили. Время на чистой машине: ~30 минут.

## 1. Заполнить `.env`

```bash
cp .env.prod.example .env
```

Сгенерировать секреты и подставить в `.env`:

```bash
echo "POSTGRES_PASSWORD=$(openssl rand -hex 32)"
echo "MEILI_MASTER_KEY=$(openssl rand -hex 32)"
echo "REVERB_APP_SECRET=$(openssl rand -hex 32)"
echo "REVERB_APP_KEY=$(openssl rand -base64 20)"
echo "MINIO_ROOT_PASSWORD=$(openssl rand -hex 32)"
echo "MAIN_APP_KEY=base64:$(openssl rand -base64 32)"
echo "DISCOGS_APP_KEY=base64:$(openssl rand -base64 32)"
```

Минимум полей которые обязательны:

```dotenv
COMPOSE_PROJECT_NAME=muzilla
APP_ENV=production
APP_DEBUG=false

POSTGRES_PASSWORD=...                         # сгенерировать
MEILI_MASTER_KEY=...                          # сгенерировать
REVERB_APP_KEY=...                            # сгенерировать
REVERB_APP_SECRET=...                         # сгенерировать

MAIN_APP_KEY=base64:...                       # сгенерировать
DISCOGS_APP_KEY=base64:...                    # сгенерировать
DISCOGS_API_TOKEN=placeholder                 # внутренний токен мiej-сервиса (можно любой непустой)

# Внутри docker-сети сервисы видят друг друга по имени контейнера:
NUXT_LARAVEL_URL=http://main-web
NUXT_BACKEND_BASE_URL=http://main-web
NUXT_DISCOGS_BASE_URL=http://discogs-web

# Yandex Maps — обязательно, иначе SSR упадёт при первом рендере главной.
# Заглушка валидна по форме; в проде впиши реальный ключ.
NUXT_PUBLIC_YMAPS_API_KEY=00000000-0000-0000-0000-000000000000
```

## 2. Проверить права на исходники (один раз)

Если репо клонирован под `umask 077` (часто на macOS), у некоторых файлов/каталогов
права `700/600` — Docker COPY копирует как есть, и PHP-FPM (`www-data`) не может их прочитать:

```bash
find main discogs -type d -not -path '*/node_modules/*' -not -path '*/vendor/*' -exec chmod 755 {} +
find main discogs -type f -not -path '*/node_modules/*' -not -path '*/vendor/*' -exec chmod 644 {} +
```

## 3. Сборка образов

```bash
make build
```

При билде Nuxt подхватит build-args из `.env` (`NUXT_LARAVEL_URL`, `NUXT_BACKEND_BASE_URL`,
`NUXT_PUBLIC_YMAPS_API_KEY` и др.) — эти значения **запекаются в bundle**.

## 4. Запуск стека и миграции

```bash
make up
docker compose -f compose.stage.yml ps   # все Up/healthy
make logs                                 # понаблюдать 30 сек
make migrate                              # 81 миграция main + 21 discogs
```

Если меняли `POSTGRES_PASSWORD` после первого `make up`, удали постгрес-volume — иначе
init-скрипт уже отработал со старым паролем:

```bash
make down
docker volume rm muzilla-stage_pg_data
make up && make migrate
```

## 5. Demo-данные (опционально)

```bash
make seed-demo
```

Создаёт:
- 4 demo-аккаунта (admin/buyer/seller/store)
- Категории, бренды, ~150 товаров, 38 новостей, FAQ
- Тестового пользователя в `discogs`

Аккаунты после `seed-demo`:

| Email | Пароль | Роль |
|-------|--------|------|
| `admin@muzilla.ru` | `password` | super-admin |
| `test@example.com` | `password123` | buyer |
| `alex@musicstore.com` | `password123` | seller |
| `info@musicmarket.ru` | `store123` | store |

Картинки тянутся с picsum.photos — если сеть Docker не выпускает, изображения
будут placeholder'ами; данные при этом всё равно создаются.

## 6. Smoke-тест

```bash
bash scripts/deploy/health-check.sh --url http://localhost
# /                       → 200 (Nuxt SSR)
# /health                 → 200 (edge nginx)
# /api/auth/me            → 401 при Accept: application/json (302 на /login без него)
# /sanctum/csrf-cookie    → 204
```

Полный flow login:

```bash
curl -sc /tmp/cj http://localhost/sanctum/csrf-cookie
XSRF=$(grep XSRF-TOKEN /tmp/cj | awk '{print $7}' | python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))')
curl -sb /tmp/cj -c /tmp/cj http://localhost/api/auth/login \
  -X POST -H "Accept: application/json" -H "X-XSRF-TOKEN: $XSRF" \
  -H "Content-Type: application/json" \
  -d '{"login":"test@example.com","password":"password123"}'
curl -sb /tmp/cj http://localhost/api/auth/me -H "Accept: application/json"
```

Должно вернуть JSON с user.id=2.

## 7. Открыть в браузере

```
http://localhost/          # Главная Nuxt
http://localhost/login     # Форма входа
```

---

---

# Prod (3 VM)

Запускать **только после успешного stage**. Stage и prod собираются из одного и того же
кода, но имеют разные compose-файлы и BUILD-args для Nuxt.

## Что нужно

- **VM-1 (Edge)** — VPS с публичным IP, Ubuntu 24.04, ~4 vCPU / 8GB / 80GB SSD.
- **VM-2 (App)** — VPS, Ubuntu 24.04, ~4 vCPU / 8GB / 40GB SSD. Закрыта от внешки, видна только VM-1.
- **VM-3 (Data)** — dedicated сервер с 128GB RAM. **Если железо ещё не приехало —** см. раздел
  «Временный VM-3 на VPS» ниже: пока берём обычную VPS, потом мигрируем без даунтайма.
- **Домен** с A-записью на IP VM-1 (например `mzt.nadev.ru`).
- **Заполненные GitHub Secrets** + публичные пакеты в GHCR (см. «Первичная настройка GitHub Actions»).

## Временный VM-3 на VPS

Пока dedicated в стойке. Поднимаем VM-3 на обычной VPS-ке. Когда железо приедет —
миграция через `pg_dumpall | psql` без переписывания .env на VM-1/VM-2 (только подменим
`VM3_HOST`).

**Требования к временной VM-3:** 4 vCPU / 8GB RAM / 80GB SSD. Postgres + Meilisearch +
MinIO легко влезают, demo-нагрузка стенда не пиковая. Selectel/Timeweb/Hetzner CX32.

```bash
# Локально — залить ssh-ключ и запустить provision:
ssh-copy-id -i ~/.ssh/muzilla_deploy.pub root@<TEMP_VM3_IP>
scp scripts/provision/{common,vm3-data}.sh root@<TEMP_VM3_IP>:~/
ssh root@<TEMP_VM3_IP> 'bash ~/vm3-data.sh'
```

Скрипт интерактивно спросит публичные IP VM-1 и VM-2 для UFW-whitelist (порты 5432,
7700, 9000, 9001 откроются только для них).

После — на временной VM-3:

```bash
cd /opt/muzilla
cp .env.prod.example .env
nano .env             # POSTGRES_PASSWORD, MEILI_MASTER_KEY, MINIO_*
make vm3              # docker compose -f compose.vm3-data.yml up -d

# SSL для Postgres (см. отдельный раздел ниже).

# Smoke:
docker compose -f compose.vm3-data.yml exec postgres pg_isready -U muzilla
```

Дальше деплой VM-1/VM-2 идёт как обычно — указываешь `VM3_HOST=<TEMP_VM3_IP>` в их `.env`.

## 1. Провижининг VM-1 и VM-2

```bash
# С локальной машины:
scp scripts/provision/{common,vm2-app}.sh root@<VM2_IP>:~/
ssh root@<VM2_IP> 'bash ~/vm2-app.sh'

scp scripts/provision/{common,vm1-edge}.sh root@<VM1_IP>:~/
ssh root@<VM1_IP> 'bash ~/vm1-edge.sh'
```

Скрипты установят Docker, настроят firewall, swap, склонируют репо в `/opt/muzilla` и
создадут UFW-правила. Caddy (SSL) ставится в составе `vm1-edge.sh`. SSH-hardening не
запустится без `/root/.ssh/authorized_keys` — `ssh-copy-id` сделай заранее.

## 2. `.env` на каждой VM

```bash
# На каждой VM:
cd /opt/muzilla
cp .env.prod.example .env
nano .env
```

Заполни **те же ключи что для stage**, плюс prod-специфичные:

```dotenv
APP_ENV=production
APP_DEBUG=false

POSTGRES_PASSWORD=<новый_секрет>
MEILI_MASTER_KEY=<новый_секрет>
REVERB_APP_KEY=<новый_секрет>
REVERB_APP_SECRET=<новый_секрет>
MAIN_APP_KEY=base64:<новый_секрет>
DISCOGS_APP_KEY=base64:<новый_секрет>
DISCOGS_API_TOKEN=<реальный_токен_внутреннего_сервиса>

# IP-адреса VM в приватной сети:
VM2_HOST=10.0.0.2
VM3_HOST=10.0.0.3
PUBLIC_HOST=mzt.nadev.ru                     # домен с SSL
MAIN_APP_URL=https://mzt.nadev.ru
DISCOGS_APP_URL=https://mzt.nadev.ru

REVERB_HOST=mzt.nadev.ru
REVERB_PORT=443
REVERB_SCHEME=https

# Nuxt: build-args для пересборки, если нужно. Обычно образ берётся из GHCR
# (собран в CI с дефолтами http://main-web/discogs-web — это правильно для VM-1).
NUXT_PUBLIC_YMAPS_API_KEY=<реальный_yandex_maps_key>

MINIO_ROOT_USER=muzilla
MINIO_ROOT_PASSWORD=<новый_секрет>
```

**Важно:** `POSTGRES_PASSWORD` на VM-3 и Laravel-параметры в `.env` на VM-1 должны совпадать,
иначе Laravel не сможет подключиться к Postgres.

## 3. Запуск (порядок: VM-3 → VM-2 → VM-1)

```bash
# На VM-3:
make vm3
docker compose -f compose.vm3-data.yml exec postgres pg_isready -U muzilla   # должен сказать "accepting connections"

# На VM-2:
make vm2
docker compose -f compose.vm2-app.yml exec redis redis-cli ping              # → PONG

# На VM-1:
make vm1
docker compose -f compose.vm1-edge.yml exec main php artisan migrate --force
docker compose -f compose.vm1-edge.yml exec discogs php artisan migrate --force

# Опционально demo-данные:
docker compose -f compose.vm1-edge.yml exec main composer require --dev fakerphp/faker --no-interaction
docker compose -f compose.vm1-edge.yml exec main php artisan db:seed --force
```

## 4. SSL (Caddy на VM-1)

После запуска Docker-стека:

```bash
sudo systemctl enable caddy
sudo systemctl start caddy
# Caddy сам получит SSL-сертификат от Let's Encrypt:
curl -I https://mzt.nadev.ru
```

Caddy конфиг — `scripts/provision/Caddyfile`, по умолчанию проксирует на edge nginx
контейнера на `127.0.0.1:8080`.

## 5. SSL для PostgreSQL (VM-3)

Dedicated сервер VM-3 ходит к VM-1/VM-2 через публичную сеть. Postgres работает через SSL.
После первого `make vm3`:

```bash
PG_DATA="/var/lib/docker/volumes/muzilla-data_pg_data/_data"
docker compose -f compose.vm3-data.yml stop postgres
openssl req -new -x509 -days 3650 -nodes \
    -out $PG_DATA/server.crt \
    -keyout $PG_DATA/server.key \
    -subj '/CN=muzilla-postgres'
chmod 600 $PG_DATA/server.key
chown 999:999 $PG_DATA/server.key $PG_DATA/server.crt
docker compose -f compose.vm3-data.yml start postgres
```

В `.env` на VM-1 добавь `DB_SSLMODE=verify-full` (или `require` для упрощённой проверки).

## 6. Финальная проверка

```bash
# С локальной машины:
bash scripts/deploy/health-check.sh --url https://mzt.nadev.ru
make health   # SSH-проверка всех трёх VM
```

## 7. Миграция временного VM-3 → dedicated (когда железо приедет)

Без даунтайма — Postgres переезжает, всё остальное (приложение на VM-1/VM-2) меняет
только адрес БД в `.env` и перезапускает свои контейнеры.

```bash
# На dedicated:
ssh-copy-id -i ~/.ssh/muzilla_deploy.pub root@<DEDICATED_IP>
scp scripts/provision/{common,vm3-data}.sh root@<DEDICATED_IP>:~/
ssh root@<DEDICATED_IP> 'bash ~/vm3-data.sh'
ssh root@<DEDICATED_IP>
cd /opt/muzilla
cp .env.prod.example .env
nano .env             # !!! POSTGRES_PASSWORD ровно тот же, что был на временной VM-3
make vm3
# Настроить SSL для Postgres (см. п. 5 выше)
exit

# На временной VM-3 — сделать дамп и закрыть запись:
ssh root@<TEMP_VM3_IP>
cd /opt/muzilla
docker compose -f compose.vm3-data.yml exec -T postgres pg_dumpall -U muzilla > /tmp/full.sql
# Опционально — переключить Postgres в read-only на время миграции:
docker compose -f compose.vm3-data.yml exec -T postgres psql -U muzilla -c "ALTER SYSTEM SET default_transaction_read_only = on; SELECT pg_reload_conf();"
scp /tmp/full.sql root@<DEDICATED_IP>:/tmp/full.sql
exit

# На dedicated — залить дамп:
ssh root@<DEDICATED_IP>
docker compose -f compose.vm3-data.yml exec -T postgres psql -U muzilla -d postgres < /tmp/full.sql
exit

# Переключить VM-1 и VM-2 на новый VM3_HOST:
for host in <VM1_IP> <VM2_IP>; do
    ssh root@$host "cd /opt/muzilla && sed -i 's/^VM3_HOST=.*/VM3_HOST=<DEDICATED_IP>/' .env"
done

# Перезапуск Laravel контейнеров на VM-1 и очередей на VM-2:
ssh root@<VM1_IP> 'cd /opt/muzilla && make vm1'
ssh root@<VM2_IP> 'cd /opt/muzilla && make vm2'

# Проверка:
make health
bash scripts/deploy/health-check.sh --url https://mzt.nadev.ru
```

После успешной проверки — сносим временную VPS-ку (`docker compose down -v` + удаляем
сервер у хостера). Также обновить `VM3_HOST` в **GitHub Secrets** (Settings → Secrets).

Опционально — для нулевого даунтайма используй `pglogical`/`pg_basebackup` репликацию
вместо `pg_dumpall`, но для бета-нагрузки 30-секундный простой обычно приемлем.

---

# Обновление (rolling deploy)

```bash
# Автоматически: push в main → GitHub Actions
# - build.yml собирает 5 образов и пушит в GHCR
# - deploy.yml идёт по SSH на VM-3 → VM-2 → VM-1, pull + restart

# Вручную с локальной машины:
make deploy-all          # все серверы (VM-3 → VM-2 → VM-1)
make deploy-vm1          # только VM-1
```

# Мониторинг

```bash
make health                                    # SSH-проверка всех VM
bash scripts/deploy/health-check.sh --url https://mzt.nadev.ru   # по URL

# Telegram-алерты (cron на VM-1):
# */5 * * * * /opt/muzilla/scripts/deploy/monitor.sh
```

# Makefile shortcuts

```bash
make help                            # справка по всем целям

# Stage:
make build / up / down / logs        # сборка / запуск / останов / логи
make migrate                         # миграции main + discogs
make seed-demo                       # demo-данные с аккаунтами
make pull                            # обновить образы из GHCR
make deploy                          # pull + up -d

# Prod (3 VM):
make vm1 / vm2 / vm3                 # pull + up -d на каждой VM
make vm1-logs / vm2-logs / vm3-logs

# Деплой:
make deploy-all                      # SSH-deploy на все VM
make deploy-vm1 / vm2 / vm3          # отдельно

# Провижининг:
make provision-vm1 / vm2 / vm3       # первоначальная настройка серверов
```

# Troubleshooting

| Симптом | Причина | Решение |
|---------|---------|---------|
| `password authentication failed for user "muzilla"` | Postgres-volume инициализирован старым паролем | `docker volume rm muzilla-stage_pg_data` (или `down -v`) |
| `Permission denied include(/var/www/html/app/...)` | Каталоги/файлы 700/600 на хосте | `find main discogs -type d -exec chmod 755 {} +; find main discogs -type f -exec chmod 644 {} +` |
| Nuxt: `You must specify apikey for createYmapsOptions` | Пустой `NUXT_PUBLIC_YMAPS_API_KEY` при билде | Заполнить в `.env`, `make build` пересобирает Nuxt |
| Nuxt: `fetch failed http://localhost:8000/api/auth/me` | Build-args для Nuxt не передались, в bundle fallback URL | Проверить `compose.stage.yml` `nuxt.build.args` и `.env`, пересобрать `nuxt` |
| `Cannot assign null to property X of type string` | Service читает `config(...)` где env пуст; ловушка `config()` defaults | Поставить default в config-файле (`env('X', '')`), либо `protected string $x = ''` |
| `Class "Faker\Factory" not found` при `db:seed` | Prod-образ собран с `--no-dev` | `composer require --dev fakerphp/faker` внутри контейнера |
| Edge `502 Connection refused` после рестарта main-web | nginx закэшировал старый IP upstream | `docker compose restart edge` |
