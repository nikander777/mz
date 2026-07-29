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

**Подводные камни импорта.** `ProductObserver::saving()` при заданном `release_id` синхронно ходит в Discogs API — на массовой загрузке это тысячи внешних запросов, поэтому сохранение идёт внутри `ProductObserver::withoutDiscogsSync()`, а `release_id` не трогается, если не изменился. По той же причине Scout отключён на время записи: индекс обновляется разом по всем затронутым лотам в конце (`Product::whereIn(...)->searchable()`). Транзакция — на порцию строк, а не на весь файл. Статусы `sold`/`deleted` из выгрузки не считаются ошибкой, если совпадают с текущим, иначе выгруженный файл не загрузился бы обратно.

## Как тестировать

**Покрытие:** 🟡 частично (в составе Profile ~40). Пробел: форма (ПВЗ/цвет/грейды/фото), привязка Discogs, продажа из коллекции, синхронизация остатка с Meili. Важно: остаток менять только через `Product::decreaseStock/increaseStock` (иначе Scout не триггерится). См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллер | `app/Http/Controllers/Api/Profile/ProductsController.php` |
| Сервисы | `app/Services/{DiscogsReleaseService,ProductSlugger}.php` |
| Модели | `app/Models/{Product,Collection}.php` |
| Джоба | `app/Jobs/ProcessImageThumbnails.php` |
| Frontend | `nuxt/pages/seller/index.vue`, `nuxt/components/seller/{MusicProductForm,HifiProductForm,ProductPhotoUpload,AddProductModal}.vue` |
| Экспорт/импорт: формат | `app/Support/ProductSheetSchema.php` — единый источник колонок, справочников и алиасов |
| Экспорт/импорт: бэкенд | `app/Exports/SellerProducts*.php`, `app/Services/ProductIo/*`, `app/Jobs/ProcessProductImport.php`, `app/Models/ProductImport.php` |
| Экспорт/импорт: фронт | `nuxt/components/seller/ProductImportModal.vue`, `nuxt/composables/useProductImportExport.ts` |
| Экспорт/импорт: тесты | `tests/Feature/Products/{ProductImportTest,ProductRowMapperTest}.php`, `tests/Feature/Profile/ProductExportTest.php` |

