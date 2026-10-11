# Каталог и поиск

> Приоритет: **P1**. Актуально на 2026-07-05.

## Назначение

Поиск и просмотр товаров маркетплейса (сервис `main`, движок Meilisearch с фасетами) и каталога дискографии — артисты, релизы, мастера, лейблы (сервис `discogs`). Гибридная гидрация: поиск в Meili, догрузка данных из БД.

## Endpoints

| Метод | Путь | Контроллер | Назначение |
|---|---|---|---|
| `GET` | `/api/search` · `/search/suggest` | `Api\SearchController` | Глобальный поиск и подсказки |
| `GET` | `/api/public/products` | `Api\Public\ProductsController::index` | Каталог с фильтрами |
| `GET` | `/api/public/products/filters` | `filters()` | Динамические фасеты |
| `GET` | `/api/public/products/{id}` | `show()` | Карточка товара |
| `GET` | `/api/public/products/{id}/similar` · `/related` | — | Похожие / связанные |
| `GET` | `/api/disco/{releases,artists,masters,labels}/{id}` · `/disco/search` | discogs | Дискография |
| `GET` · `POST` | `/api/public/products/counts-by-release` | `countsByRelease()` → `Catalog\ReleaseStockService` | Товары витрины по discogs_id релизов: `counts` + `singles` (id/slug единственного товара). GET — до 200 id, POST — до 20 000 (фильтр «В наличии») |
| `GET` | `/api/disco/artists/{id}/discography?mode=index` · `?only_masters=…&only_releases=…` | discogs `ArtistController::discography` | Шаги фильтра «В наличии»: лёгкий индекс всех элементов / полные данные только для страницы |

## Дискография ↔ товары

discogs не знает о товарах, main не знает артистов и мастеров (в `main.releases` только `discogs_id`). Связку собирает Nuxt-прокси (`server/utils/marketplace.ts`, `server/api/disco/artists/[id]/discography.get.ts`).

- **Счётчик «N товаров»** считается по `Product::scopeCatalogVisible` — тем же условиям, что у витрины (active, остаток > 0, есть ПВЗ, `can_sell` продавца, раздел не скрыт). Число совпадает с каталогом по ссылке.
- **Куда ведёт кнопка** (`nuxt/utils/marketplaceLink.ts`): один товар на релиз/мастер — сразу карточка лота; несколько — `/catalog?release_id=a,b,c` (версии с товарами). `release_id` в каталоге принимает CSV (до 500 id) в DB- и Meili-ветке. `master_id` каталог не понимает и не должен — фильтр мастера = список его версий.
- **Фильтр «В наличии»** (`in_stock=1`, включён по умолчанию на странице артиста): прокси берёт у discogs `mode=index`, одним POST спрашивает main об остатках, отбирает элементы с товарами, пагинирует сам и догружает страницу через `only_*`. Если main или discogs не поддерживают шаг — отдаётся обычный список с `in_stock_unavailable: true`.

## Как тестировать

**Покрытие:** 🟡 ~18 (Collections/Disco). Пробел: полнотекстовый Meili-поиск товаров, поведение фасетов. Важно: фасеты намеренно не зависят от цены; счётчик — planner-оценка. См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллеры | `app/Http/Controllers/Api/SearchController.php`, `Api/Public/ProductsController.php` |
| Сервис | `app/Services/Catalog/CatalogSearchService.php` |
| Модели | `app/Models/Product.php` (Searchable); `discogs`: `Release/Artist/Label/Master` |
| Frontend | `nuxt/pages/index.vue`, каталог, `nuxt/components/ProductCard.vue` |
| Интеграции | Meilisearch (`config/scout`), Discogs (микросервис) |

