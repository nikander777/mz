# MONETA_* на VM-2: проброс и порядок выкатки

> Runbook для прода (VM-1 `90.156.211.143`, VM-2 `85.193.81.19`). Общая схема
> серверов и креды — `DEPLOY.md`, эталон переменных — `.env.prod.example`.

## Симптом и причина

`main-queue` и `main-scheduler` на VM-2 крутят `ReconcileMonetaContractsJob`
(каждые 30 мин), `ReconcileSellerBalances` (ежечасно), `ReconcileMonetaPayments`
(каждые 10 мин), `InitiateSellerPayout` и `ActivateMonetaUnitJob` (ставится в
очередь коллбеком на VM-1, выполняется на VM-2). Все они ходят в НКО МОНЕТА
через `config('services.moneta.*')`.

До 05.09.2026 якорь `x-laravel-env` в `compose.vm2-app.yml` пробрасывал
`PAYMENTS_*`/`BPA_*`, но ни одной `MONETA_*`, а в `/opt/muzilla/.env` на VM-2
этих ключей не было вовсе (`grep -c '^MONETA_' .env` = 0). В результате джобы
стартовали без учётных данных, писали `getProfile упал` / `не удалось прочитать
счёт` в warning и завершались «успешно»: договоры продавцов не переходили в
ACTIVE, расчётные шлюзы не создавались, выплаты не инициировались.

Отдельная грабля: `MONETA_TEST_MODE` в `config/services.php` по умолчанию `true`.
Незаданная переменная на VM-2 означала бы demo-режим у фоновых задач при боевом
вебе.

## Что изменилось в репозитории

- `compose.vm2-app.yml` — в `x-laravel-env` добавлен блок `MONETA_*` +
  `MZ_REQUIRE_MONETA_APPROVAL`, зеркально `compose.vm1-edge.yml` (те же ключи,
  те же прод-дефолты: `MONETA_TEST_MODE:-false`, `MONETA_USE_STUB:-false`,
  `MONETA_API_URL:-https://www.moneta.ru`). Demo-ключи `MONETA_TEST_SBP_*` из
  `compose.stage.yml` на прод намеренно не переносятся.
- `.env.prod.example` — блок МОНЕТЫ помечен «нужен на VM-1 и VM-2».
- `scripts/deploy/env-append.sh` — безопасный append в `.env` (см. ниже).
- `scripts/deploy/deploy.sh`, `.github/workflows/prod-deploy.yml` — перед
  `compose pull/up` добивают перевод строки в конце `.env`.

Значения секретов в git не попадают: в compose только `${MONETA_*}`, реальные
значения живут в `/opt/muzilla/.env` на каждой VM.

## Порядок выкатки

Порядок важен: сначала `git pull` без `up -d`, потом значения, потом точечный
recreate. `deploy.sh --vm2` делает `up -d` для всего стека и пересоздал бы
media-воркеры посреди батча.

### 1. Обновить ops-репо на VM-2 (без пересоздания контейнеров)

```bash
ssh root@85.193.81.19 'cd /opt/muzilla && git pull origin main'
```

### 2. Проверить `.env` на VM-2 до правок

```bash
ssh root@85.193.81.19 'cd /opt/muzilla && grep -c "^MONETA_" .env; bash scripts/deploy/env-append.sh --check'
```

Ожидаемо до переноса: `0` и предупреждения `--check`, если файл без перевода
строки в конце или в нём есть склеенные строки (см. раздел «Склейка»). Склейки
разобрать до следующего шага.

### 3. Перенести значения с VM-1 одной трубой

Секреты не оседают на локальной машине и не печатаются: скрипт логирует только
имена ключей.

```bash
ssh root@90.156.211.143 "grep -E '^(MONETA_[A-Z0-9_]+|MZ_REQUIRE_MONETA_APPROVAL)=' /opt/muzilla/.env" \
  | ssh root@85.193.81.19 'cd /opt/muzilla && bash scripts/deploy/env-append.sh --stdin'
```

Что делает `env-append.sh`: проверяет `tail -c1 .env` и при необходимости
добавляет перевод строки, пропускает ключи, которые уже есть в файле (с
предупреждением), дописывает остальные. Если какой-то `MONETA_*` на VM-2 уже был
с другим значением, он будет пропущен: сравните руками и при необходимости
повторите с `--replace` (перед заменой скрипт делает бэкап
`.env.bak-append-<timestamp>`).

Пустые значения (`MONETA_ATTR_TAX_REGIME=`, `MONETA_WEBHOOK_ALLOWED_IPS=` и т.п.)
переносятся как есть: ключ с пустым значением означает «не отправлять», а
отсутствующий ключ дал бы warning compose и дефолт из конфига.

Перенос даёт паритет с VM-1, не больше. Если на VM-1 ключ пуст, на VM-2 он тоже
будет пуст: на 05.09.2026 на VM-1 пусты `MONETA_API_KEY` и
`MONETA_PAYMENT_PASSWORD` (ЛК1 «Счета», который в НКО к тому же заблокирован).
Сверка договоров и балансов через ЛК2 от этого не зависит; легаси-выплаты и
фискальные возвраты через ЛК1 — отдельный хвост, не этого runbook'а.

### 4. Убедиться, что compose видит все переменные

```bash
ssh root@85.193.81.19 'cd /opt/muzilla && docker compose -f compose.vm2-app.yml config >/dev/null 2>/tmp/compose-warn.txt; grep MONETA /tmp/compose-warn.txt || echo "MONETA_*: все переменные заданы"'
```

`config` пишет в stderr строку `variable is not set` для каждого незаданного
ключа. После переноса упоминаний `MONETA` там быть не должно.

### 5. Пересоздать только main-queue и main-scheduler

Переменные попадают в контейнер только при пересоздании (entrypoint делает
`config:cache`), `restart` не помогает.

```bash
ssh root@85.193.81.19 'cd /opt/muzilla && docker compose -f compose.vm2-app.yml up -d --no-deps --force-recreate main-queue main-scheduler'
```

Не трогаем: `main-queue-media` (длинные батчи переноса фото, таймаут 900 с),
`reverb`, `discogs-queue`, `discogs-scheduler`. Им `MONETA_*` не нужны.
Следующий полный `deploy.sh --vm2` / `up -d` пересоздаст и их, потому что хеш
конфигурации сервисов изменился. Это штатно, но делать в спокойное окно:
прерванный батч media-воркера уйдёт в retry (`--tries=3`).

### 6. Проверить конфиг внутри контейнера (без вывода секретов)

На VM-2:

```bash
cd /opt/muzilla
docker compose -f compose.vm2-app.yml exec -T main-queue php artisan tinker --execute='
  echo "unit_registered: ", config("services.moneta.unit_id_registered_group") !== "" ? "set" : "MISSING", PHP_EOL;
  echo "username(LK2):   ", config("services.moneta.username") !== "" ? "set" : "MISSING", PHP_EOL;
  echo "api_login(LK1):  ", config("services.moneta.api_login") !== "" ? "set" : "MISSING", PHP_EOL;
  echo "test_mode:       ", var_export((bool) config("services.moneta.test_mode"), true), PHP_EOL;
  echo "use_stub:        ", var_export((bool) config("services.moneta.use_stub"), true), PHP_EOL;
  echo "require_approval:", var_export(config("marketplace.seller_gate.require_moneta_approval"), true), PHP_EOL;
'
```

Ожидаемо: все `set`, `test_mode: false`, `use_stub: false`,
`require_approval: true` (как на VM-1).

### 7. Прогнать сверку и посмотреть логи

```bash
docker compose -f compose.vm2-app.yml exec -T main-queue php artisan tinker \
  --execute='App\Jobs\ReconcileMonetaContractsJob::dispatch();'
sleep 30
docker compose -f compose.vm2-app.yml logs --since=5m main-queue \
  | grep -E 'ReconcileMonetaContractsJob|ReconcileSellerBalances'
```

До фикса в логе `ReconcileMonetaContractsJob: getProfile упал` с ошибкой
авторизации или «не задан MONETA_UNIT_REGISTERED». После — `старт` →
`сверка завершена` без `упал`. Если дисп��тч не появился в логе вовсе,
проверьте залипший unique-лок `laravel_unique_job:reconcile-moneta-contracts:all`
в Redis (джоб `ShouldBeUnique`, прецедент описан в `DEPLOY.md`).

## Склейка строк в `.env` (прецедент PAYMENTS_PLATFORM_PHONE)

На VM-2 `PAYMENTS_PLATFORM_PHONE` однажды дописали через `echo >> .env` в файл
без перевода строки в конце. Получилась одна строка
`DISCOGS_API_URL=https://muzilla.ruPAYMENTS_PLATFORM_PHONE=7922...`: телефон
площадки пропал, а адрес дискографии стал битым, и фоновые задачи, которым нужен
релиз, тихо получали «не найдено».

Диагностика (на любой VM, в `/opt/muzilla`):

```bash
bash scripts/deploy/env-append.sh --check
grep -n 'PAYMENTS_PLATFORM_PHONE' .env   # ключ обязан стоять в начале строки
```

`--check` берёт список ключей из `.env.prod.example` и ищет их не в начале
строки. Исправление:

```bash
cp -p .env .env.bak-unglue-$(date +%Y%m%d-%H%M%S)
sed -i 's/\(.\)PAYMENTS_PLATFORM_PHONE=/\1\nPAYMENTS_PLATFORM_PHONE=/' .env
bash scripts/deploy/env-append.sh --check
docker compose -f compose.vm2-app.yml up -d --no-deps --force-recreate main-queue main-scheduler
```

Профилактика: любые новые ключи в живой `.env` только через
`scripts/deploy/env-append.sh` (или `--stdin` для блока с другой VM). Деплой
(`deploy.sh`, `prod-deploy.yml`) перед `compose up` вызывает
`env-append.sh --ensure-newline`, так что файл без завершающего `\n` больше
не доживает до следующего append.

## Откат

Лишние ключи в `.env` безвредны, пока compose их не пробрасывает, поэтому
откат — это откат compose-файла:

```bash
cd /opt/muzilla
git revert <sha коммита с блоком MONETA в compose.vm2-app.yml>   # или git checkout <prev> -- compose.vm2-app.yml
docker compose -f compose.vm2-app.yml up -d --no-deps --force-recreate main-queue main-scheduler
```

## Чеклист для новых переменных в `x-laravel-env`

1. Добавить ключ в `compose.vm1-edge.yml` **и** `compose.vm2-app.yml`, если его
   читает что-то в queue/scheduler (почти всегда да: джобы используют тот же
   `config/`).
2. Прописать в `.env.prod.example` с пометкой, на каких VM он нужен.
3. На каждой VM: `bash scripts/deploy/env-append.sh KEY=VALUE`.
4. Пересоздать затронутые контейнеры (`--no-deps --force-recreate <service>`).
