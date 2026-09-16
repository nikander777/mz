# Жизненный цикл заказа

> Каноничная карта того, как заказ проходит путь от создания до завершения (или отмены): кто и чем двигает статус, какие джобы работают в фоне, какие события и уведомления при этом стреляют.
> Приоритет: **P0** (ядро маркетплейса). Актуально на 2026-07-05.

## Действующие лица

| Актор | Роль в процессе |
|---|---|
| **Покупатель** | Создаёт/подтверждает заказ, оплачивает, при проблеме открывает спор |
| **Продавец** | Подтверждает оплаченный заказ (окно 48ч), отправляет, взаимодействует по спору |
| **Платформа** (`main`) | Валидирует переходы (FSM), взводит дедлайны, шлёт уведомления, инициирует выплату |
| **Планировщик** (cron-джобы) | Автоотмена неподтверждённых, автозавершение доставленных, поллинг доставки |
| **Модератор** (админка) | Разрешает споры (`DISPUTED` → завершение/возврат) |

## Где что хранится

| Таблица / модель | Что лежит |
|---|---|
| `orders` (`Order`) | `status`, `payment_status`, `delivery_status` + временны́е метки: `payment_at`, `seller_confirmation_deadline`, `seller_confirmed_at`, `shipped_at`, `delivered_at`, `payout_eligible_at`, `completed_at`, `cancelled_at`, `disputed_at`; выплата: `seller_payout_amount/at/status/id`; деньги: `moneta_*` |
| `order_status_history` (`OrderStatusHistory`) | `from_status`, `to_status`, `changed_by` (null = автоматический переход), `comment` — журнал каждого перехода |
| `order_shipments` (`OrderShipment`) | отправление: `delivery_method`, `tracking_number`, `qr_code_url`, `qr_pdf_url`, `status`, `tracking_data`, `provider_uuid` |
| `order_items`, `order_addresses`, `order_messages`, `order_complaints` | позиции, адрес-снимок, переписка по заказу, жалобы/споры |

Окна: подтверждение продавцом — 48 ч (`Order::sellerConfirmationHours()`, для СБП и карты значения разные). Передача посылки перевозчику — **48 ч от оформления заказа** (`Order::shippingDeadlineAt()`, `config/marketplace.php → shipping`); подтверждение продавцом этот срок не сдвигает. Удержание денег — `min(shipped_at + 24д, delivered_at + 17д)`, задаётся в `config/marketplace.php → payout` (`Order::computePayoutEligibleAt()`).

**Отметку об отправке ставит перевозчик, не продавец.** Ручной кнопки «Заказ отправлен» больше нет (роут `POST /api/orders/{order}/ship` удалён): `shipped_at` проставляет `CheckDeliveryStatus` по факту приёмки груза, а у СДЭК заведённая заявка (`CREATED`/`ACCEPTED`) считается `AWAITING_SHIPMENT`, а не отправкой. Ручной перевод в `SHIPPED` остался только у администратора (`OrderService::markShippedManually()`, админский `updateStatus`) — на случай, когда перевозчик молчит.

## Обзор жизненного цикла

```mermaid
stateDiagram-v2
  [*] --> PENDING: заказ создан (checkout)
  PENDING --> CONFIRMED: accept() / confirm()
  CONFIRMED --> PAID: оплата (webhook Moneta)
  PAID --> PROCESSING: sellerConfirm() ≤48ч
  PAID --> CANCELLED: таймаут 48ч (джоба) / sellerDecline()
  PROCESSING --> SHIPPED: приёмка груза перевозчиком (CheckDeliveryStatus)
  PROCESSING --> CANCELLED: посылка не сдана за 48ч от оформления (джоба) + возврат
  PAID --> CANCELLED: посылка не сдана за 48ч от оформления (джоба) + возврат
  SHIPPED --> DELIVERED: посылка в ПВЗ (CheckDeliveryStatus)
  DELIVERED --> COMPLETED: вручение (CheckDeliveryStatus)
  SHIPPED --> COMPLETED: якорь отправки, вручение не подтверждено
  SHIPPED --> DISPUTED: dispute()
  DELIVERED --> DISPUTED: dispute()
  COMPLETED --> DISPUTED: dispute() до выплаты
  PENDING --> CANCELLED: cancel()
  CONFIRMED --> CANCELLED: cancel()
  COMPLETED --> [*]
  CANCELLED --> [*]
  REFUNDED --> [*]
```

## Статусы заказа (`App\Enums\OrderStatus`)

| Статус | Значение | Лейбл (UI) | Смысл |
|---|---|---|---|
| `PENDING` | `pending` | На рассмотрении | Заказ создан, ждёт подтверждения |
| `CONFIRMED` | `confirmed` | Подтвержден | Ожидается оплата |
| `PAID` | `paid` | Ожидает подтверждения продавца | Оплачен, окно продавца 48ч |
| `PROCESSING` | `processing` | Подтверждён продавцом | Накладная создана, посылка ещё не принята перевозчиком; передать её нужно в пределах 48ч от оформления заказа |
| `SHIPPED` | `shipped` | Отправлен | Передан в доставку |
| `DELIVERED` | `delivered` | Доставлен | Посылка в пункте выдачи, ждёт получателя |
| `COMPLETED` | `completed` | Завершен | Покупатель забрал заказ. Статус витринный: деньги продавцу разблокируются отдельно, по окончании окна удержания |
| `CANCELLED` | `cancelled` | Отменен | Отменён (в т.ч. автоотмена) |
| `REFUNDED` | `refunded` | Возврат средств | Выполнен возврат |
| `DISPUTED` | `disputed` | Спор | Ждёт решения модератора |

Правила переходов зашиты в методы enum: `isFinal()` (`COMPLETED/CANCELLED/REFUNDED`), `isCancellable()` (`PENDING/CONFIRMED/PAID`), `isCancellableByAdmin()` (то же + `PROCESSING`: подтверждённый заказ закрывает поддержка), `canSellerConfirm()` (`PAID`), `canBuyerDispute()` (`SHIPPED/DELIVERED`; полное правило — `Order::canBuyerDispute()`: в `COMPLETED` спор доступен, пока выплата не инициирована), `canBuyerReview()`/`allowsProductReview()` — см. [Отзывы](/processes/reviews).

Отдельные enum'ы: `PaymentStatus` (`pending/processing/completed/failed/cancelled/refunded`), `DeliveryStatus` (`pending/awaiting_shipment/shipped/in_transit/arrived/delivered/returned/cancelled/error`).

## Endpoints

Группа `Route::middleware(['auth:web', EnsurePhoneIsVerifiedApi])->prefix('orders')`, контроллер `Api\Orders\OrderController`.

| Метод | Путь | Контроллер | Переход |
|---|---|---|---|
| `GET` | `/api/orders` | `index()` | — (список по роли buyer/seller) |
| `GET` | `/api/orders/{order}` | `show()` | — (детали + все связи) |
| `POST` | `/api/orders/{order}/confirm` | `confirm()` | `PENDING → CONFIRMED` (покупатель) |
| `POST` | `/api/orders/{order}/accept` | `accept()` | `PENDING → CONFIRMED` (продавец) |
| `POST` | `/api/orders/{order}/pay` | `pay()` | `CONFIRMED → PAID` (stub-оплата) |
| `POST` | `/api/orders/{order}/seller-confirm` | `sellerConfirm()` | `PAID → PROCESSING` + создание отправления |
| `POST` | `/api/orders/{order}/seller-decline` | `sellerDecline()` | `PAID → CANCELLED` + возврат |
| `POST` | `/api/orders/{order}/ship` | `ship()` | `PROCESSING → SHIPPED` |
| `POST` | `/api/orders/{order}/cancel` | `cancel()` | `→ CANCELLED` (возврат склада/денег) |
| `POST` | `/api/orders/{order}/dispute` | `dispute()` | `SHIPPED/DELIVERED → DISPUTED` |

Реальная оплата приходит не через `/pay`, а вебхуком Moneta — см. [Платежи](/processes/payments-moneta).

## Переходы: сервис `OrderService`

`app/Services/Order/OrderService.php` — единственная точка смены статуса (пишет `OrderStatusHistory`, диспатчит события):

| Метод | Переход | Побочный эффект |
|---|---|---|
| `markAsPaid()` | `CONFIRMED → PAID` | `seller_confirmation_deadline = now + 48ч`; событие `OrderPaid` |
| `sellerConfirmOrder()` | `PAID → PROCESSING` | событие `OrderSellerConfirmed` → создание отправления |
| `sellerDeclineOrder()` | `PAID → CANCELLED` | возврат денег |
| `markShippedManually()` | `PROCESSING → SHIPPED` | только админ; заполняет `shipped_at` у заказа и отправления, событие `OrderShipped` |
| `autoCancelUnconfirmedOrder()` | `PAID → CANCELLED` | вызывается джобой по истечении дедлайна подтверждения |
| `autoCancelUnshippedOrder()` | `PAID/PROCESSING → CANCELLED` | вызывается джобой, когда посылка не сдана за 48ч от оформления |
| `cancelOrder()` | `* → CANCELLED` | возврат товаров на склад + денег (если деньги получены) |
| `cancelOrderByAdmin()` | `* → CANCELLED` | то же, но разрешён и `PROCESSING` |
| `openDisputeByBuyer()` | `SHIPPED/DELIVERED → DISPUTED` | создаёт `OrderComplaint` |

## Фоновая автоматизация (джобы + расписание)

Расписание — `main/routes/console.php`.

| Джоба | Частота | Что делает |
|---|---|---|
| `CancelUnconfirmedPaidOrders` | каждый час | `PAID` с истёкшим `seller_confirmation_deadline` → `CANCELLED` + возврат |
| `SendUnconfirmedOrderReminders` | каждый час | напоминания продавцу через 3/6/24/36ч (антидубль по `confirmation_reminder_stage`) |
| `SendUnshippedOrderReminders` | каждый час | напоминания продавцу о несданной посылке (12/24/36ч от оформления, антидубль по `shipping_reminder_stage`) |
| `CancelUnshippedOrders` | каждый час | `PAID`/`PROCESSING` старше 48ч от оформления и без `shipped_at` → `CANCELLED` + возврат. Перед отменой перевозчик опрашивается напрямую: недоступное API = отмена откладывается |
| `ReportStuckShipments` | каждые 6 часов | дайджест админам: заявки в `ERROR`, просроченные автоотмены, молчащий трекинг |
| `cdek:retry-failed-shipments` | каждые 30 минут | автоповтор заявок СДЭК, упавших в `ERROR` |
| `CheckDeliveryStatus` | каждый час | поллинг трека (СДЭК API v2 / Почта SOAP; на demo — таймер-стаб 1д→в пути, 3д→ПВЗ, 5д→доставлено). Прибытие в ПВЗ → `DELIVERED`, вручение → `COMPLETED` + `OrderDelivered` + `OrderCompleted` |
| `ReleaseDeliveredOrders` | каждый час | невыплаченные (`seller_payout_status IS NULL`) с `payout_eligible_at ≤ now` и без спора → `InitiateSellerPayout`; заказы, вручение которых перевозчик не подтвердил, заодно доводит до `COMPLETED` |
| `RefreshPendingCdekShipments` | каждые 15 минут | добор трек-номера и PDF-накладной СДЭК |

## События и уведомления

Регистрация слушателей — `app/Providers/AppServiceProvider.php`.

| Событие | Слушатель | Действие |
|---|---|---|
| `OrderPaid` | `SendOrderPaidNotification` | письмо + in-app продавцу |
| `OrderSellerConfirmed` | `CreateShipmentOnSellerConfirmed` | заявка перевозчику, QR/накладная, письмо продавцу |
| `OrderShipped` | `SendOrderShippedNotification` | уведомление покупателю |
| `OrderShipped` | `SetPayoutWindowOnShipped` | взводит `payout_eligible_at` по якорю отправки |
| `OrderDelivered` | `DispatchSellerPayoutOnDelivered` | пересчитывает `payout_eligible_at` (не выплачивает) |
| `OrderDelivered` | `SendOrderDeliveredNotification` | уведомление покупателю |
| `OrderCompleted` | `SendOrderCompletedNotification` | уведомление продавцу |
| `OrderCancelled` | `SendOrderCancelledNotification` | уведомление сторонам |

`OrderDelivered` также диспатчится из `Order::booted()` при смене `delivery_status → delivered`.

## Что делать, если пошло не так

| Ситуация | Поведение системы | Кто чинит |
|---|---|---|
| Продавец не подтвердил за 48ч | `CancelUnconfirmedPaidOrders` → авто-`CANCELLED` + возврат | автоматически |
| Посылка не сдана за 48ч от оформления | напоминания (12/24/36ч) → `CancelUnshippedOrders` → авто-`CANCELLED` + возврат | автоматически |
| API перевозчика недоступен | автоотмена откладывается до подтверждённого ответа; вебхук СДЭК (`/api/webhook/cdek/{secret}`) и поллинг дублируют друг друга; заявки в `ERROR` пересоздаются по расписанию | автоматически, эскалация — `ReportStuckShipments` |
| Перевозчик не подтвердил вручение | `ReleaseDeliveredOrders` завершает по якорю отправки (24д) | автоматически |
| Статусы доставки не двигаются | проверить `order_shipments.tracking_data.last_checked_at` и лог `CDEK: неизвестный код статуса`; дожать `php artisan delivery:advance {номер заказа}` | поддержка |
| Спор открыт (`DISPUTED`) | заказ исключён из автовыплаты, деньги на транзите | модератор (админка) |
| Вебхук доставки/оплаты потерялся | поллинг `CheckDeliveryStatus` / статусы Moneta досверяются | автоматически (fallback-джобы) |
| Отмена уже оплаченного | `cancelOrder()` возвращает склад и деньги | покупатель/продавец/поддержка |

## Как тестировать

**Приоритет P0.** Ключевые проверки — полный «счастливый путь» и ветки автоматики:

1. `checkout → PAID → sellerConfirm → SHIPPED → DELIVERED (ПВЗ) → COMPLETED (вручение)` (с проверкой `OrderStatusHistory` на каждом шаге).
2. Автоотмена: `PAID` без подтверждения + перевод часов → `CANCELLED` + возврат (джоба `CancelUnconfirmedPaidOrders`).
3. Разблокировка денег: истечение окна удержания → `InitiateSellerPayout` (по уже завершённому заказу тоже).
4. Спор: `dispute()` из `SHIPPED/DELIVERED` → заказ не уходит в автовыплату.
5. Отмена оплаченного → возврат склада и денег.

**Покрытие автотестами:** `tests/Feature/Orders/OrderConfirmationFlowTest.php` (~15) + `EndToEndPaymentFlowTest.php` (4 сквозных). **Пробел:** ветки спора и edge-кейсы автоотмены — см. [матрицу покрытия](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Статусы | `app/Enums/{OrderStatus,PaymentStatus,DeliveryStatus}.php` |
| Endpoints | `main/routes/api.php` (группа `orders`), `app/Http/Controllers/Api/Orders/OrderController.php` |
| Переходы | `app/Services/Order/OrderService.php` |
| Джобы | `app/Jobs/{CancelUnconfirmedPaidOrders,ReleaseDeliveredOrders,CheckDeliveryStatus,SendUnconfirmedOrderReminders,RefreshPendingCdekShipments}.php` |
| Расписание | `main/routes/console.php` |
| События/слушатели | `app/Providers/AppServiceProvider.php`, `app/Events/Order*`, `app/Listeners/*` |
| Модели | `app/Models/Order/{Order,OrderStatusHistory,OrderShipment,OrderItem}.php` |
| Тесты | `tests/Feature/Orders/OrderConfirmationFlowTest.php`, `tests/Feature/EndToEndPaymentFlowTest.php` |
