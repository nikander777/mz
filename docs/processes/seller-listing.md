# Продажа товара продавцом

> Приоритет: **P1**. Актуально на 2026-07-05.

## Назначение

Выставление товара на продажу: новый товар или из личной коллекции; заполнение деталей (состояние, цвет, грейды, ПВЗ, фото), привязка к релизу Discogs (автозаполнение метаданных), индексация в Meili. Единая форма для продажи и для коллекции.

## Endpoints

Группа `profile`, контроллер `Api\Profile\ProductsController`.

| Метод | Путь | Назначение |
|---|---|---|
| `GET`/`POST` | `/api/profile/products` | Список / создание |
| `GET`/`PUT`/`DELETE` | `/api/profile/products/{product}` | Карточка / обновление / удаление |
| `PATCH` | `/api/profile/products/{product}/status` | Статус (active/draft/inactive) |
| `POST` | `/api/profile/products/bulk-update` | Массовое обновление |
| `GET` | `/api/profile/collections/{collection}/sell` | Продажа из коллекции |
| `POST` | `/api/discogs/select-release` · `/sync-product-release` | Привязка к релизу Discogs |

Экспорт/импорт файлом, контроллер `Api\Profile\ProductImportExportController`. Префикс `products-io`, а не `products/...`: `Route::resource('products')` перехватил бы путь своим `products/{product}`.

| Метод | Путь | Назначение |
|---|---|---|
| `GET` | `/api/profile/products-io/export` | Выгрузка лотов (xlsx/csv), учитывает фильтры кабинета |
| `GET` | `/api/profile/products-io/template` | Пустой шаблон со строкой-примером |
| `GET`/`POST` | `/api/profile/products-io/imports` | История загрузок / приём файла |
| `GET` | `/api/profile/products-io/imports/{import}` | Состояние загрузки (поллинг прогресса) |
| `GET` | `/api/profile/products-io/imports/{import}/errors` | Отчёт об ошибках построчно |
| `DELETE` | `/api/profile/products-io/imports/{import}` | Удалить запись истории |
| `POST` | `/api/profile/products-io/ozon/check` | Перенос с Ozon: проверка ключа Seller API |
| `POST` | `/api/profile/products-io/ozon/imports` | Перенос с Ozon: запуск (ход — те же `imports/{import}`), см. [Перенос товаров с Ozon](../overview/ozon-import) |

**Подводные камни импорта.** `ProductObserver::saving()` при заданном `release_id` синхронно ходит в Discogs API — на массовой загрузке это тысячи внешних запросов, поэтому сохранение идёт внутри `ProductObserver::withoutDiscogsSync()`, а `release_id` не трогается, если не изменился. По той же причине Scout отключён на время записи: индекс обновляется разом по всем затронутым лотам в конце (`Product::whereIn(...)->searchable()`). Транзакция — на порцию строк, а не на весь файл. Статусы `sold`/`deleted` из выгрузки не считаются ошибкой, если совпадают с текущим, иначе выгруженный файл не загрузился бы обратно.

**Где лежит файл.** Веб принимает файл на VM-1, а разбирает его воркер очереди на VM-2 — это разные машины с разными файловыми системами, поэтому local-диск не годится: до 19.09.2026 все импорты на проде падали с «Не удалось прочитать файл: файл не найден на диске», а локально и на стейдже воспроизвести это было нельзя (там контейнеры делят один том). Диск задаётся `PRODUCT_IMPORT_DISK` — в проде `s3-private`, отдельный приватный бакет, потому что `muzilla-images` публичен на чтение и приватный ACL объекта там не действует. С нелокального диска файл скачивается во временный, парсеру нужен файл на диске. Очередь — `PRODUCT_IMPORT_QUEUE` (`imports`, воркер `main-queue-imports`): разбор 5000 строк идёт минутами и в `default` придерживал бы письма и платежи.

**Подраздел выводится из формата.** В форме музыки поля «Подраздел» нет — продавец выбирает только «Формат» (`Vinyl` / `CD` / `Cassette` / `Box Set`), который пишется в `products.release_format`. Подраздел каталога проставляет `ProductObserver::saving()` через `App\Support\MediaSubcategory`: `Vinyl` → «Виниловая пластинка (LP 12\")», `CD` → «CD Album», `Cassette` → «Кассета». Без этого шага новый товар не попадал ни в навигацию `/catalog/<slug>`, ни в фильтр «Подраздел», а в карточке формат показывался как «Разное» — ровно та же дыра, что оставил legacy-импорт.

Товару с привязкой к дискографии подраздел ставится точнее: `release_format` хранит только имена носителей («Vinyl»), потому что фасет «Формат» группирует по цельной строке и уточнения раздробили бы бакеты, — а `DiscogsReleaseService::formatWithDescriptions()` отдаёт «Vinyl, 7\", Single», откуда выводится «Виниловая пластинка (EP/Single 7\")». Подраздел из чужой категории не назначается: формат винила у Hi-Fi лота (проигрывателя) пластинкой его не сделает, а явный выбор продавца в Hi-Fi форме не перетирается. Пересчёт происходит при смене формата.

Формат `Box Set`, выбранный руками, подраздела не даёт — по одной этой строке неизвестно, винил это или CD; такой лот остаётся без подраздела, но в фильтре «Формат» виден в бакете «Бокс-сет». Товарам, созданным до появления этой логики, подраздел доливает `php artisan products:backfill-subcategory` (см. [Операции](/processes/operations#миграция-с-legacy-портала)).

## Форма лота: фото и количество

**Порядок фото.** Продавец перетаскивает миниатюры в `ProductPhotoUpload` (`sortablejs`, на телефоне после короткого удержания). Первое фото главное, и оно же обложка лота в каталоге и ЛК: всё читается из `photo_0…photo_9`, отдельного признака обложки нет.

Форма шлёт `photo_order` — JSON-список, где уже загруженное фото записано путём, а новое файлом `new:N` (N — индекс в `photos[]`). Без общего списка нельзя понять, где среди старых стоит новое, и оно всегда оказывалось бы в конце. `existing_photos` оставлен для старых клиентов: файлы, которых нет в списке, дописываются в конец. Смена порядка переставляет только пути, файлы не пересобираются.

**Количество.** `stock_quantity` — целое от 1 до `Product::MAX_STOCK_QUANTITY`. Распроданный лот можно сохранить с нулём, иначе правка описания вынуждала бы вернуть его в продажу.

При редактировании форма шлёт ещё `stock_quantity_original` — остаток на момент открытия. Пока форма открыта, лот могут купить, и прямая запись вернула бы проданные единицы:

- число не меняли → остаток не пишется вовсе;
- поменяли → условный `UPDATE ... WHERE stock_quantity = original`; если остаток успел измениться, ответ `422` с `current_stock`, и форма подставляет актуальное значение.

**Списание.** Остаток резервируется при оформлении заказа (`decreaseStockAtomically`), а не после оплаты, и возвращается при любой отмене. См. [Оформление заказа](/processes/checkout).

**Статус при нуле.** Распроданный лот остаётся `active`: из каталога он пропадает по условию `stock_quantity > 0`, страница товара открывается и показывает «Нет в наличии», а при отмене заказа или пополнении лот сам возвращается в продажу. Статус `sold` дал бы 404 на странице товара. Отметку «Продан» показывает только `SellerProductCard` в «Мои лоты» — по остатку, статус для неё не меняется.

## Как тестировать

**Покрытие:** 🟡 частично (в составе Profile ~40). Пробел: форма (ПВЗ/цвет/грейды), привязка Discogs, продажа из коллекции, синхронизация остатка с Meili. Важно: остаток менять только через `Product::decreaseStock/increaseStock` (иначе Scout не триггерится). См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллер | `app/Http/Controllers/Api/Profile/ProductsController.php` |
| Сервисы | `app/Services/{DiscogsReleaseService,ProductSlugger}.php` |
| Модели | `app/Models/{Product,Collection}.php` |
| Джоба | `app/Jobs/ProcessImageThumbnails.php` |
| Frontend | `nuxt/pages/seller/index.vue`, `nuxt/components/seller/{MusicProductForm,HifiProductForm,ProductPhotoUpload,ProductQuantityCounter,AddProductModal}.vue`, `nuxt/composables/useProductStockField.ts`, `nuxt/utils/productPhotoForm.ts` |
| Экспорт/импорт: формат | `app/Support/ProductSheetSchema.php` — единый источник колонок, справочников и алиасов |
| Экспорт/импорт: бэкенд | `app/Exports/SellerProducts*.php`, `app/Services/ProductIo/*`, `app/Jobs/ProcessProductImport.php`, `app/Models/ProductImport.php` |
| Экспорт/импорт: фронт | `nuxt/components/seller/ProductImportModal.vue`, `nuxt/composables/useProductImportExport.ts` |
| Экспорт/импорт: тесты | `tests/Feature/Products/{ProductImportTest,ProductRowMapperTest}.php`, `tests/Feature/Profile/ProductExportTest.php` |

