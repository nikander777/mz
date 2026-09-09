# Индекс `releases` в проде: план восстановления

Ранбук на случай, когда индекс дискографии в Meilisearch перестаёт принимать
записи. Составлен 09.09.2026 после инцидента с петлёй рестартов.

Смежное: [`production-env.md`](production-env.md) · [`../processes/catalog-search.md`](../processes/catalog-search.md)

---

## Что известно

`releases` на проде повреждён на уровне LMDB. Симптомы двойные: часть задач
записи падает штатно с ``Index `releases`: internal: decoding failed.``, часть
уводит процесс в segfault индексирующего потока (`ld-musl-x86_64.so.1`, exit
139). **Чтение при этом работает** — поиск и фильтры по releases отдают 200.

Порча тянется с 16.06.2026; 28.08 инстанс восстановили из дампа в новый том
`meili_data_v2`, но добить `releases` до полного объёма не удалось: при массовой
заливке индекс дважды деградировал в то же состояние. Ошибки идут из
`milli::update::new::indexer` — нового индексатора, появившегося в v1.12.
Прежняя версия 1.6.2 в июне залила 16.7 млн документов за 3 часа без потерь
(1533 док/с против 400 у нового).

09.09 воркеры добора обложек на VM-2 непрерывно писали в этот индекс, и Meili
уходил в петлю: поднимался, ~20 секунд отвечал, снова падал на том же батче.
158 рестартов. Петлю сняли остановкой воркеров и отменой задач
(`POST /tasks/cancel?statuses=enqueued,processing&indexUids=releases`).

## Текущее состояние (09.09.2026)

| | документов | размер | покрытие |
|---|---:|---:|---:|
| Postgres `releases` | 19 026 346 | — | 100% |
| Meili `releases` (боевой) | 7 157 166 | 24.1 GiB | **37.6%** |
| Meili `releases_new` (лежит рядом) | 12 394 000 | 37.0 GiB | **65.1%** |

Настройки обоих индексов (`searchableAttributes`, `filterableAttributes`,
`sortableAttributes`, `rankingRules`, `distinctAttribute`, `displayedAttributes`)
совпадают полностью — сверено 09.09.

Восстановиться из бэкапа нельзя: единственный снапшот
`/meili_data/snapshots/data.ms.snapshot` от 31.08 (25 ГБ) уже с порчей,
`dumps/` пуст.

> **Воркеры `muzilla-discogs-queue*` и `muzilla-discogs-scheduler` на VM-2
> остановлены с 09.09.** Массовый добор обложек на паузе. Поднимать их до
> этапа 2 нельзя — снова уронят Meili.

---

## Этап 1. Swap: 37% → 65% за секунду

Самое дешёвое действие. `releases_new` полнее боевого на 5,2 млн документов, а
`POST /swap-indexes` меняет их местами атомарно и без простоя.

```bash
ssh root@92.255.105.112
KEY=$(docker inspect muzilla-meilisearch-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MEILI_MASTER_KEY | cut -d= -f2-)
curl -s -X POST -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  --data '[{"indexes": ["releases", "releases_new"]}]' \
  http://127.0.0.1:7700/swap-indexes
```

Проверка — число документов в боевом индексе должно стать 12,4 млн:

```bash
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:7700/indexes/releases/stats
curl -s -o /dev/null -w '%{http_code}\n' 'https://muzilla.ru/api/disco/releases?per_page=1'
```

**Откат:** та же команда ещё раз — swap симметричен.

**Риск:** низкий. `releases_new` собирался тем же `disco:meili-index` и с теми
же настройками, но деградировал на 12,4 млн, то есть с большой вероятностью
тоже не принимает записи. Для чтения это не важно — важно для этапа 2.

---

## Этап 2. Диагностика: принимает ли индекс записи

От ответа зависит, нужна ли пересборка вообще. Делать **после** деплоя фикса
`SCOUT_QUEUE` + `updateQuietly` (mz.main 42a3d30, mz 2531817) — с ним падение
Meili больше не роняет авторизованный API, максимум моргает каталог.

```bash
# один документ из боевой БД, тем же путём, что ходит инкрементальный Scout-синк
ssh root@85.193.81.19
docker exec muzilla-discogs-queue-1 php artisan disco:meili-index releases --limit=1 --wait
```

Затем смотреть статус задачи и живость процесса:

```bash
ssh root@92.255.105.112
curl -s -H "Authorization: Bearer $KEY" 'http://127.0.0.1:7700/tasks?indexUids=releases&limit=3'
docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' muzilla-meilisearch-1
```

- **Задача `succeeded`, счётчик рестартов не вырос** → индекс рабочий. Поднять
  воркеры (этап 5), пересборка не нужна.
- **`failed` с `decoding failed` или рестарт** → путь записи мёртв, идти на
  этап 3.

---

## Этап 3. Изолированный стенд: доказать причину, не трогая прод

Прошлый раз пересборку гоняли прямо на боевом инстансе, и она дважды съела
34,6 часа впустую. Прежде чем повторять — воспроизвести деградацию на отдельном
инстансе. Место есть: на VM-3 свободно 2,8 ТБ.

```bash
ssh root@92.255.105.112
docker run -d --name meili-lab-1531 -p 127.0.0.1:7701:7700 \
  -v meili_lab_1531:/meili_data \
  -e MEILI_MASTER_KEY="$KEY" -e MEILI_ENV=production -e MEILI_NO_ANALYTICS=true \
  getmeili/meilisearch:v1.53.1

docker run -d --name meili-lab-162 -p 127.0.0.1:7702:7700 \
  -v meili_lab_162:/meili_data \
  -e MEILI_MASTER_KEY="$KEY" -e MEILI_ENV=production -e MEILI_NO_ANALYTICS=true \
  getmeili/meilisearch:v1.6.2
```

Залить в каждый полный `releases` из Postgres, переопределив хост на лету:

```bash
ssh root@85.193.81.19
docker exec -e MEILISEARCH_HOST=http://92.255.105.112:7701 muzilla-discogs-queue-1 \
  php artisan search:configure
docker exec -d -e MEILISEARCH_HOST=http://92.255.105.112:7701 muzilla-discogs-queue-1 \
  php artisan disco:meili-index releases --batch=2000 --max-queue=4
```

`--max-queue` вместо `--wait`: держит очередь Meili короткой, но не ждёт каждый
батч (полный `--wait` даёт ~400 док/с). Прогон детачнутый, читать прогресс через
`docker logs`.

Что смотреть: на каком числе документов появляется первая задача со статусом
`failed`. Ожидание по прошлым данным — 1.53.1 деградирует в районе 12,4 млн,
1.6.2 доходит до конца.

**Нагрузка:** чтение 19 млн строк из боевого Postgres на VM-3. Postgres там уже
узкое место дискографии — гонять только ночью.

---

## Этап 4. Перенос результата в прод

По итогу этапа 3 — одна из двух развилок.

### 4а. Заливка на 1.53.1 доходит до конца (деградация не воспроизвелась)

Значит дело было в конкретном прогоне, а не в версии. Собрать «рядом» прямо на
боевом инстансе и сделать swap:

```bash
docker exec -d muzilla-discogs-queue-1 \
  php artisan disco:meili-index releases --index=releases_v3 --batch=2000 --max-queue=4
# по завершении
curl -X POST ... --data '[{"indexes": ["releases", "releases_v3"]}]' .../swap-indexes
```

### 4б. Держит только 1.6.2

Прод придётся переводить на версию, которая переваривает заливку. Путь
1.6.2 → дамп → импорт уже отработан 28.08.

⚠️ **Ловушка:** импорт дампа в Meilisearch заменяет инстанс целиком. Дамп со
стенда содержит только `releases` — импортировать его в боевой инстанс нельзя,
снесёт `products`, `sellers`, `artists`, `masters`, `labels`. Нужен дамп,
собранный из всех индексов сразу: залить на стенд не только releases, но и
остальные (`disco:meili-index all` + перенос `products`/`sellers` из main),
снять `POST /dumps`, поднять новый том с `--import-dump`, переключить
`MEILISEARCH_HOST`. Это полноценное окно обслуживания, не быстрая операция.

Дампы 1.6.2 (формат V6) в 1.53.1 импортируются без нареканий — проверено.

---

## Этап 5. Вернуть воркеры добора обложек

Только после того, как боевой `releases` принимает записи.

```bash
ssh root@85.193.81.19
docker start $(docker ps -a --format '{{.Names}}' | grep -E '^muzilla-discogs-(queue|scheduler)')
```

Первые 10 минут держать под наблюдением:

```bash
watch -n 10 "ssh root@92.255.105.112 docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' muzilla-meilisearch-1"
```

---

## Чего не делать

- **Не запускать `disco:meili-index` без `--max-queue` или `--wait`.** Батчи
  уходят быстрее, чем Meili их переваривает, очередь копится, Meili группирует
  по 20–48 тысяч документов и падает на post-processing. Так уже потеряли
  7875 задач.
- **Не доверять `decoding failed` как диагнозу входных данных.** Те же документы
  в чистый индекс заходят нормально; ошибка про внутреннее состояние индекса.
- **Не удалять `releases_new`** до завершения всей операции — это единственная
  копия, которая полнее боевой.
- **Не поднимать воркеры обложек «на попробовать»** — каждый прогон добавляет
  историю упавших задач, `tasks/data.mdb` уже доходила до 986 МБ.

## Слепые зоны мониторинга

`monitor.sh` дёргает `/api/disco/releases` и смотрит тело `/api/search`, cron
`*/5` на VM-1 стоит. Но алертов нет: в `/opt/muzilla/scripts/deploy/.env.deploy`
не заданы `TELEGRAM_BOT_TOKEN` и `TELEGRAM_CHAT_ID`, без них скрипт отрабатывает
молча. Прошлый раз это стоило двух месяцев мёртвой дискографии.
