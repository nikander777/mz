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

