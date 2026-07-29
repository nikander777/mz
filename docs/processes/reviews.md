# Отзывы

> Приоритет: **P1**. Актуально на 2026-07-05.

## Назначение

Полиморфные отзывы о продавце и товарах. Отзыв создаётся **только из завершённого заказа** (как у Ozon): `order_id` + `verified_purchase`. Успешная сделка → отзыв о продавце и товарах; неуспешная → только о продавце. Soft delete.

## Endpoints

| Метод | Путь | Контроллер | Назначение |
|---|---|---|---|
| `GET` | `/api/public/reviews` · `/reviews/stats` | `Api\ReviewController` | Публичное чтение + статистика |
| `GET` | `/api/public/products/{product}/reviews` | — | Отзывы о товаре |
| `GET` | `/api/public/sellers/{seller}/reviews` | — | Отзывы о продавце |
| `GET`/`POST` | `/api/orders/{order}/reviews` | `Api\Orders\OrderReviewController` | Отзывы по заказу (создание только отсюда) |
| `PUT`/`DELETE` | `/api/profile/reviews/{review}` | `Api\ReviewController` | Редактировать / удалить свой |
| `PUT`/`DELETE` | `/api/profile/reviews/{review}/reply` | `Api\Profile\ReviewReplyController` | Ответ продавца: сохранить / удалить |

Доступность создания — по `OrderStatus::canBuyerReview()` / `allowsProductReview()` (см. [жизненный цикл](/processes/order-lifecycle#статусы-заказа-app-enums-orderstatus)).

**Фильтр по оценке.** `productReviews` и `sellerReviews` принимают `?rating=1..5`; некорректное значение молча игнорируется. В ответе — `rating_distribution` (оценка → количество), посчитанное **до** применения фильтра: иначе вкладки схлопывались бы после первого же выбора.

**Ответ продавца.** Хранится прямо в отзыве (`reviews.seller_reply`, `seller_replied_at`) — ответ всегда один, отдельная таблица ничего не добавляет. Право отвечать определяется адресатом отзыва, а не ролью: `Review::isRepliableBy()` сверяет `reviewable` (User → сам продавец, Product → `products.user_id`). Текст проходит тот же фильтр мата (`NoProfanity`), что и отзыв. `ReviewResource` отдаёт `can_reply` — по нему фронт рисует кнопку. Админский `Admin\ReviewController::reply` пишет в то же поле (раньше он только логировал текст и терял его).

## Как тестировать

**Покрытие:** 🔴 **0** (пробел). Ключевые проверки: создание только из заказа, полиморфизм продавец/товар, дедуп (не 3→6), soft delete, `verified_purchase`. См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллеры | `app/Http/Controllers/Api/ReviewController.php`, `Api/Orders/OrderReviewController.php`, `Api/Profile/ReviewReplyController.php` |
| Сервис | `app/Services/Order/OrderReviewService.php` |
| Модель | `app/Models/Review.php` (полиморфный `reviewable`: Product\|User; `order_id`, `deleted_at`, `seller_reply`) |
| Фильтр мата | `app/Services/ProfanityFilter.php`, `app/Rules/NoProfanity.php`, `config/profanity.php` |
| Frontend | `nuxt/components/{ReviewCard,ReviewsList,ReviewForm,OrderReviewModal,UserReviewCard,UserReviewEdit}.vue` |
| Тесты | `tests/Feature/Reviews/{SellerReplyTest,ReviewRatingFilterTest,ReviewProfanityTest,ReviewVisibilityTest}.php` |

