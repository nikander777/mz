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

Константы окон (в `Order`): `SELLER_CONFIRMATION_HOURS = 48`, `PAYOUT_HOLD_HOURS = 48`.

## Обзор жизненного цикла

```mermaid
stateDiagram-v2
  [*] --> PENDING: заказ создан (checkout)
  PENDING --> CONFIRMED: accept() / confirm()
  CONFIRMED --> PAID: оплата (webhook Moneta)
  PAID --> PROCESSING: sellerConfirm() ≤48ч
  PAID --> CANCELLED: таймаут 48ч (джоба) / sellerDecline()
  PROCESSING --> SHIPPED: ship()
  SHIPPED --> DELIVERED: трекинг (CheckDeliveryStatus)
  DELIVERED --> COMPLETED: +48ч (ReleaseDeliveredOrders) → выплата
  SHIPPED --> DISPUTED: dispute()
  DELIVERED --> DISPUTED: dispute()
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
| `PROCESSING` | `processing` | Подтверждён продавцом | Готовится к отправке (создана накладная/QR) |
| `SHIPPED` | `shipped` | Отправлен | Передан в доставку |
| `DELIVERED` | `delivered` | Доставлен | Получен покупателем |
| `COMPLETED` | `completed` | Завершен | Финал: покупатель получил, инициирована выплата |
| `CANCELLED` | `cancelled` | Отменен | Отменён (в т.ч. автоотмена) |
| `REFUNDED` | `refunded` | Возврат средств | Выполнен возврат |
| `DISPUTED` | `disputed` | Спор | Ждёт решения модератора |

Правила переходов зашиты в методы enum: `isFinal()` (`COMPLETED/CANCELLED/REFUNDED`), `isCancellable()` (`PENDING/CONFIRMED/PAID`), `canSellerConfirm()` (`PAID`), `canBuyerDispute()` (`SHIPPED/DELIVERED`), `canBuyerReview()`/`allowsProductReview()` — см. [Отзывы](/processes/reviews).

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
| `shipOrder()` | `PROCESSING → SHIPPED` | заполняет `shipped_at`; событие `OrderShipped` |
| `autoCancelUnconfirmedOrder()` | `PAID → CANCELLED` | вызывается джобой по истечении дедлайна |
| `cancelOrder()` | `* → CANCELLED` | возврат товаров на склад + денег (если `PAID`) |
| `openDisputeByBuyer()` | `SHIPPED/DELIVERED → DISPUTED` | создаёт `OrderComplaint` |

## Фоновая автоматизация (джобы + расписание)

Расписание — `main/routes/console.php`.

| Джоба | Частота | Что делает |
|---|---|---|
| `CancelUnconfirmedPaidOrders` | каждый час | `PAID` с истёкшим `seller_confirmation_deadline` → `CANCELLED` + возврат |
| `SendUnconfirmedOrderReminders` | каждый час | напоминания продавцу через 3/6/24/36ч (антидубль по `confirmation_reminder_stage`) |
| `CheckDeliveryStatus` | каждые 6 часов | поллинг трека (СДЭК API v2 / Почта SOAP; на demo — таймер-стаб 1д→в пути, 3д→ПВЗ, 5д→доставлено); при доставке → `OrderDelivered` |
| `ReleaseDeliveredOrders` | каждый час | доставленные с `payout_eligible_at ≤ now` и без спора → `COMPLETED` + `OrderCompleted` + `InitiateSellerPayout` |
| `RefreshPendingCdekShipments` | каждые 15 минут | добор трек-номера и PDF-накладной СДЭК |

## События и уведомления

Регистрация слушателей — `app/Providers/AppServiceProvider.php`.

| Событие | Слушатель | Действие |
|---|---|---|
| `OrderPaid` | `SendOrderPaidNotification` | письмо + in-app продавцу |
| `OrderSellerConfirmed` | `CreateShipmentOnSellerConfirmed` | заявка перевозчику, QR/накладная, письмо продавцу |
| `OrderShipped` | `SendOrderShippedNotification` | уведомление покупателю |
| `OrderDelivered` | `DispatchSellerPayoutOnDelivered` | взводит `payout_eligible_at = delivered_at + 48ч` |
| `OrderDelivered` | `SendOrderDeliveredNotification` | уведомление покупателю |
| `OrderCompleted` | `SendOrderCompletedNotification` | уведомление продавцу |
| `OrderCancelled` | `SendOrderCancelledNotification` | уведомление сторонам |

`OrderDelivered` также диспатчится из `Order::booted()` при смене `delivery_status → delivered`.

## Что делать, если пошло не так

| Ситуация | Поведение системы | Кто чинит |
|---|---|---|
| Продавец не подтвердил за 48ч | `CancelUnconfirmedPaidOrders` → авто-`CANCELLED` + возврат | автоматически |
| Покупатель не подтвердил получение | `ReleaseDeliveredOrders` авто-завершает через 48ч после доставки | автоматически |
| Спор открыт (`DISPUTED`) | заказ исключён из автовыплаты, деньги на транзите | модератор (админка) |
| Вебхук доставки/оплаты потерялся | поллинг `CheckDeliveryStatus` / статусы Moneta досверяются | автоматически (fallback-джобы) |
| Отмена уже оплаченного | `cancelOrder()` возвращает склад и деньги | покупатель/продавец/поддержка |

## Как тестировать

**Приоритет P0.** Ключевые проверки — полный «счастливый путь» и ветки автоматики:

1. `checkout → PAID → sellerConfirm → SHIPPED → DELIVERED → COMPLETED` (с проверкой `OrderStatusHistory` на каждом шаге).
2. Автоотмена: `PAID` без подтверждения + перевод часов → `CANCELLED` + возврат (джоба `CancelUnconfirmedPaidOrders`).
3. Автозавершение: `DELIVERED` + 48ч → `COMPLETED` + инициирована выплата.
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
