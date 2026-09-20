# Операции и команды

> Консольные команды, запуск/перезапуск сервисов, переиндексация и деплой. Практическая шпаргалка для разработки и эксплуатации. Актуально на 2026-07-07.
> Точный список команд сервиса — `php artisan list` в `main/` или `discogs/`.

## Локальные dev-серверы

Порты фиксированы (не менять, не поднимать дубли):

| Сервис | Команда | Порт |
|---|---|---|
| main (Laravel) | `php artisan serve` | 8000 |
| discogs (Laravel) | `php artisan serve --port=8001` | 8001 |
| main Reverb (WebSocket) | `php artisan reverb:start` | 8080 |
| nuxt (фронтенд) | `npm run dev` | 3000 |
| docs (эта документация) | `npm run docs:dev` (в `docs/`) | 5173 |

`composer run dev` в `main/` поднимает полный стек (сервер + очередь + логи + vite).

## Очереди и планировщик

- **Очередь:** `php artisan queue:listen --tries=1` (или `queue:work`). Через очередь идут фоновые задачи: обработка вебхуков оплаты, выплаты продавцам, создание отправлений, генерация миниатюр.
- **Планировщик:** периодические джобы описаны в `main/routes/console.php`. Ключевые (см. [Жизненный цикл заказа](/processes/order-lifecycle#фоновая-автоматизация-джобы-расписание)): автоотмена неподтверждённых (каждый час), автозавершение доставленных (каждый час), поллинг доставки (каждые 6ч), напоминания продавцу, добор накладных СДЭК. В проде планировщик запускается по cron (`php artisan schedule:run` раз в минуту).

## Поиск (Meilisearch)

Каталог товаров (`main`) и дискография (`discogs`) работают через Meili (драйверы конфигурируются env: `MZ_CATALOG_DRIVER_PRODUCTS`, `DISCO_CATALOG_DRIVER`).

- `php artisan search:configure` — применить настройки индексов (фильтруемые/сортируемые атрибуты).
- `php artisan products:meili-index` — переиндексировать товары (main).
- `php artisan disco:meili-index {releases|artists|masters|labels}` — переиндексировать дискографию (discogs).
- `php artisan scout:renew` — общая переиндексация Scout. ⚠️ В `main` НЕ переиндексирует продавцов (модель `User`) — отдельно: `php artisan scout:import "App\Models\User"`.
- Остаток товара синхронизируется в Meili только через `Product::decreaseStock/increaseStock` (прямой `increment/decrement` не триггерит Scout).

> Порядок раскатки каталога на Meili: `search:configure` → `*:meili-index` → флип env-драйвера.

## Кеш и прогрев

- Фасеты каталога кешируются (TTL ~10 мин). «Холодные» тяжёлые фасеты (артисты) могут отдавать 504 — прогрев через `scripts/deploy/warm-cache.php` (tinker), HTTP-прогрев не помогает.
- Сброс кеша: `php artisan cache:clear`, конфиг — `php artisan config:clear`.

## Доставка

- `php artisan cdek:retry-failed-shipments` — повторная попытка создать зависшие отправления СДЭК.
- Трекинг обновляется поллингом (джобы `CheckDeliveryStatus`, `RefreshPendingCdekShipments`), не вебхуками. См. [Доставка](/processes/delivery).

## Миграция с legacy-портала

Носитель товара (винил / CD / кассета / DVD / бокс-сет) в старой БД лежит **не** в `products.category_id` — там у 99,9% лотов корень дерева «Музыка». Реальный тип носителя записан в `products.common_properties` (JSON, закодированный **дважды**) под ключом `subcategory_id`. Первый импорт читал только `category_id`, поэтому все 582k legacy-товаров приехали без подраздела и без формата: в карточке показывалось «Разное», фильтры «Подраздел» и «Формат» видели 0,4% витрины.

- `php artisan migrate-old:backfill-media-type` — доливает подраздел (`subcategory_id`) и формат (`release_format`) уже мигрированным товарам по `legacy_id`, не трогая остальные поля. Полный реимпорт ради двух колонок не нужен.
- Логика резолва — `App\Console\Commands\Migration\Maps\MediaTypeMap` (её же использует `migrate-old:products`).

Порядок определения носителя и покрытие на дампе от 31.08.2026 (587 843 лота):

| Источник | Товаров |
|---|---|
| `common_properties.subcategory_id` | 557 529 |
| дерево legacy-категорий (Hi-Fi) | 658 |
| распознано по названию | 16 752 |
| распознано по описанию | 1 034 |
| носитель из чужой категории → пропуск | 132 |
| не определён → «Разное» | 11 738 |

Итого носитель проставляется **98%** legacy-каталога.

Что важно помнить:

- Видимые бакеты витрины — винил, CD, кассета, DVD, бокс-сет. Редкие legacy-типы (107 «Другие носители», 106 LD) формат не получают и остаются в «Разном»; SACD и катушки получают подраздел из дерева, но без формата.
- Формат из дискографии точнее: товару, привязанному к релизу с непустым `format`, `release_format` не проставляется — его заполнит `SyncProductsReleaseData`.
- Подраздел из чужой категории не пишется: «Кассетная дека» в разделе Hi-Fi не должна стать кассетой, а пластинка — Hi-Fi аппаратурой.
- Команда пишет напрямую в БД (без Eloquent), Scout об этом не знает — после прогона обязательно `php artisan products:meili-index --visible-only`, иначе фасеты останутся старыми.
- Прогон идемпотентен: по умолчанию заполняются только пустые поля, повторный запуск ничего не портит. `--overwrite` перезаписывает уже заполненные, `--no-guess` отключает распознавание по тексту, `--dry-run` считает без записи.

## Деплой и перезапуск

> DevOps-инфраструктура: прод — `muzilla.ru`, стейдж — `dev.muzilla.ru`. Контейнеры Docker Compose.

- **Стейдж:** автодеплой при push в `master` (CI собирает образ → триггерит pull+up+migrate на VM, ~7 мин). Ручной `make deploy` параллельно даёт конфликт имён контейнеров.
- **Прод:** локальный `scripts/deploy/deploy.sh --vm1` или кнопка «Deploy 3-VM prod» в GitHub Actions (нужен GHCR-логин PAT'ом).
- **Перезапуск сервиса:** `docker compose up -d --force-recreate <service>`. ⚠️ На стейдже избегать `--remove-orphans` (сносит postgres/redis).
- Bind-mount одного файла не подхватывает изменения через `sed -i` — нужен `--force-recreate`.

> ⚠️ Секрет `VM1_HOST` в Actions указывает на СТЕЙДЖ — прод-деплой из Actions может задеть стейдж. Сверяться перед запуском.

## Тесты

- `main/`: `php artisan test` — ⚠️ ~188 пре-существующих падений (нет `is_admin`, удалён Breeze web-auth, Scout/Notification pollution). Гонять **прицельно**: `php artisan test --filter=OrderConfirmationFlow`.
- `discogs/`: `php artisan test` — рабочий.
- `nuxt/`: `npm run test` (Vitest).

Матрица покрытия автотестами — [Матрица покрытия](/testing/coverage-matrix).
