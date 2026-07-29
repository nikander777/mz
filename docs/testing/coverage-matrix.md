# Матрица покрытия

> Где риски, а где уже спокойно. Сводка по автотест-покрытию критических процессов на 2026-07-05. Источник — аудит `main/tests`, `discogs/tests`, `nuxt/tests`.

## Сводная матрица

| # | Процесс | Приоритет | Автотесты (backend) | Главный пробел |
|---|---|---|---|---|
| 1 | [Регистрация / авторизация](/processes/auth) | P1 | ✅ ~23 (Auth) | 2FA, linking VK |
| 2 | [Каталог / поиск](/processes/catalog-search) | P1 | 🟡 ~18 (Collections/Disco) | Meili полнотекст, фасеты |
| 3 | [Корзина / избранное](/processes/cart-wishlist) | **P0** | 🔴 Cart **0** / Wishlist 74 (фронт) | **Cart API — 0** |
| 4 | [Оформление заказа (checkout)](/processes/checkout) | **P0** | 🔴 **0** | **весь флоу** |
| 5 | [Жизненный цикл заказа](/processes/order-lifecycle) | **P0** | 🟡 15 + E2E 4 | спор, edge автоотмены |
| 6 | [Платежи (Moneta)](/processes/payments-moneta) | **P0** | ✅ ~27 (webhook/card) | часть refund-флоу |
| 7 | [Доставка (СДЭК/Почта)](/processes/delivery) | P1 | 🟡 7 (CDEK) | ПВЗ, курьеры |
| 8 | [Выплаты продавцам](/business/seller-payouts-flow) | P1 | ✅ 7 (Payout) | отмена/reconcile |
| 9 | [Отзывы](/processes/reviews) | P1 | 🔴 **0** | **весь флоу** |
| 10 | [Продажа товара](/processes/seller-listing) | P1 | 🟡 часть Profile (40) | форма, привязка Discogs |
| — | Сообщения / диалоги | P1 | 🔴 **0** | **весь флоу + WebSocket** |

Легенда: ✅ покрыто · 🟡 частично · 🔴 не покрыто.

## Критические дыры (P0 без покрытия)

Приоритетные цели этапа автотестов — контроллеры, у которых **0 тестов** при высокой критичности:

| Контроллер | Что нужно покрыть |
|---|---|
| `Api\CartController` | add / update / remove / clear / **merge** гостевой корзины |
| `Api\Orders\CheckoutController` | расчёт стоимости, мультипродавцовая разбивка, инициация оплаты |
| `Api\ReviewController` | create / edit / delete, рейтинг продавца/товара, полиморфизм |
| `Api\MessageController`, `Api\ConversationController` | отправка/чтение, WebSocket-доставка |

## Состояние тест-сьюта

| Уровень | Инструмент | Объём | Состояние |
|---|---|---|---|
| Backend `main/` | Pest (Feature/Unit) | ~241 тест, SQLite `:memory:`, `QUEUE=sync` | ⚠️ частично: ~188 пре-существующих падений (нет колонки `is_admin`, удалён Breeze web-auth, Scout/Notification pollution) — гонять **прицельно**, не всё подряд |
| Backend `discogs/` | Pest | ~49 тестов | ✅ рабочий (поиск, фасеты, штрихкоды) |
| Frontend `nuxt/` | Vitest | ~74 теста (сторы/composables) | ✅ базовый; компоненты и страницы — 0 |
| E2E | — | нет Playwright/Cypress | 🔴 отсутствует |

> `main/` и `nuxt/` — вложенные git-репозитории. Прицельный прогон: `php artisan test --filter=...` из `main/`.

## Как поддерживать актуальность

Матрица — снимок на дату в шапке. Обновлять при: добавлении Pest/Vitest-тестов на непокрытый процесс; появлении E2E; изменении состояния сьюта. Числа сверять аудитом `tests/` соответствующего сервиса.
