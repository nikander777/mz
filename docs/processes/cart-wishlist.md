# Корзина и избранное

> Приоритет: **P0** (корзина). Актуально на 2026-07-05.

## Назначение

Серверная корзина и полиморфное избранное (товар / релиз / артист / лейбл / мастер). Для гостя корзина и избранное живут в `localStorage` и сливаются в аккаунт при входе.

## Endpoints

| Метод | Путь | Контроллер | Назначение |
|---|---|---|---|
| `GET`/`POST`/`PATCH`/`DELETE` | `/api/cart[...]` | `Api\CartController` | Корзина — см. [checkout](/processes/checkout#корзина-участвует-в-оформлении) |
| `POST` | `/api/cart/merge` | `merge()` | Слияние гостевой корзины |
| `GET` | `/api/wishlist/{type}` | `Api\FavoriteController` | Избранное по типу |
| `POST`/`DELETE` | `/api/wishlist/{type}/{id}` | — | Добавить / удалить |
| `GET` | `/api/wishlist/{type}/{id}/check` | — | Проверить статус |

## Как тестировать

**Покрытие:** 🔴 Cart API — **0** (критический пробел, P0); избранное — 74 фронт-теста (`nuxt/tests`). Ключевые проверки: гостевая корзина → merge, галочки выбора (`deselectedItemIds`), полиморфное избранное без auth (гостевые сердечки). См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллеры | `app/Http/Controllers/Api/{CartController,FavoriteController}.php` |
| Сервис | `app/Services/FavoriteService.php` |
| Модели | `app/Models/{CartItem,Favorite}.php` (Favorite — полиморфный) |
| Frontend | `nuxt/stores/{cart,wishlist}.ts`, `nuxt/pages/{cart,wishlist}.vue` |
| Хранилище гостя | `localStorage` (`useGuestCart`, гостевое избранное) |

