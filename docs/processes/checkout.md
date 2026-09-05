# Оформление заказа (checkout)

> Как товары из корзины превращаются в заказы: выбор товаров, доставка и ПВЗ, адрес получателя, разбивка по продавцам и инициация оплаты. Включает работу корзины на этапе оформления.
> Приоритет: **P0**. Актуально на 2026-07-05.

## Действующие лица

| Актор | Роль |
|---|---|
| **Покупатель** (гость или авторизованный) | Выбирает товары, доставку, вводит получателя, оплачивает |
| **Платформа** (`main`) | Считает стоимость, группирует по продавцам, создаёт заказы, инициирует платёж |
| **Перевозчики** (СДЭК / Почта России) | Расчёт стоимости и сроков, список ПВЗ |
| **DaData** | Подсказки адресов/городов/улиц |

## Где что хранится

| Модель | Что лежит |
|---|---|
| `cart_items` (`CartItem`) | `user_id`, `product_id`, `quantity` (+ вычисляемые `total_price`, `is_available`) |
| `orders` (`Order`) | один заказ = один продавец: `subtotal`, `delivery_cost`, `fee_amount`, `total_amount`, `payment_batch_id`, `source='platform'`, `customer_*` |
| `order_items` (`OrderItem`) | позиции + `product_snapshot` (снимок цены/описания на момент заказа) |
| `order_addresses` (`OrderAddress`) | адрес-снимок: ПВЗ (`pickup_point_*`) или курьер (`city`, `address_line1`) |
| `order_shipments` (`OrderShipment`) | `carrier`, `delivery_method`, `cost`, `weight` |

> Ключевой принцип: **один Order на каждого продавца**, все заказы одной корзины объединяются `payment_batch_id` и оплачиваются одним платежом.

## Обзор потока

```mermaid
flowchart TD
  Cart[Корзина: выбранные товары] --> Calc[POST /orders/calculate — предрасчёт]
  Cart --> Deliv[Выбор доставки/ПВЗ по продавцу]
  Deliv --> DS[DeliveryService → CDEK / Почта]
  Calc --> Checkout[POST /orders/checkout]
  Checkout --> CS[CheckoutService.createMultipleOrders]
  CS -->|группировка по seller_id| Orders[N заказов + payment_batch_id]
  Orders --> Pay[Инициация оплаты]
  Pay --> Moneta[Платежи Moneta]
```

## Корзина (участвует в оформлении)

Контроллер `Api\CartController`; авторизация — через `CartItem` Policy.

| Метод | Путь | Метод | Назначение |
|---|---|---|---|
| `GET` | `/api/cart` | `index()` | Корзина + summary (`total_price/items/quantity`) |
| `POST` | `/api/cart` | `store()` | Добавить (`AddToCartRequest`; проверка `stock_quantity`) |
| `PATCH` | `/api/cart/{cartItem}` | `update()` | Изменить количество |
| `DELETE` | `/api/cart/{cartItem}` | `destroy()` | Удалить позицию |
| `DELETE` | `/api/cart` | `clear()` | Очистить корзину |
| `POST` | `/api/cart/merge` | `merge()` | Слить гостевую корзину (localStorage) в БД после логина |

**Гостевая корзина** живёт в `localStorage` (`useGuestCart`), при логине `merge()` капит количество `min(existing + guest, stock, 100)`, пропуская удалённые/неактивные/свои товары; ответ `{ merged, skipped }` (идемпотентно). Подробнее о хранилищах — [Корзина и избранное](/processes/cart-wishlist).

## Endpoints checkout

Группа `orders`, контроллеры `Api\Orders\CheckoutController` и `DeliveryController`.

| Метод | Путь | Метод | Назначение |
|---|---|---|---|
| `POST` | `/api/orders/calculate` | `CheckoutController::calculate()` | Предрасчёт: subtotal + delivery + platform_fee (без создания) |
| `POST` | `/api/orders/checkout` | `CheckoutController::process()` | **Создать заказы из корзины** |
| `POST` | `/api/orders/delivery/calculate` | `DeliveryController::calculate()` | Стоимость/сроки доставки (один или все перевозчики) |
| `GET` | `/api/orders/delivery/pickup-points` | `DeliveryController::pickupPoints()` | ПВЗ по городу / координатам / bbox карты |
| `GET` | `/api/orders/delivery/courier-options` | `DeliveryController::courierOptions()` | Опции курьерской доставки |
| `POST` | `/api/orders/delivery/track` | `DeliveryController::track()` | Трекинг по номеру |

Валидация: `CalculateOrderRequest`, `CreateOrdersRequest` (методы `getCustomerData()/getOrdersData()/getDeliveryData()`, `courier_address` обязателен при `delivery_method=courier`).

## Создание заказов: `CheckoutService`

`app/Services/Order/CheckoutService.php`, единственный метод, создающий заказы, — `createMultipleOrders($buyer, $ordersData, $customerData, $deliveryData)`:

1. `resolveBatchDriver()` — драйвер платежа батча по участникам сделки (`PaymentProviderManager::forParticipants`, роллаут по allowlist покупателей/продавцов): `bpa` (касса агрегатора, чек 54-ФЗ) или `moneta` (историческая схема). Батч попадает в схему целиком.
2. `resolveSellerOrder()` для каждого продавца — серверная проверка: цена из БД, доставка из `DeliveryService`, принадлежность товара продавцу, `canSell()`. При драйвере `bpa` дополнительно фискальный гейт `SellerFiscalReadiness` (счёт в НКО, ИНН, название, телефон) → issue `seller_not_fiscal_ready`. Любая проблема → `CheckoutValidationException` → `422` + `issues`, заказы не создаются. Тот же разбор использует `previewOrders()` (`POST /api/orders/checkout/preview`), поэтому экран подтверждения и созданный заказ не расходятся.
3. `generatePaymentBatchId()` → `BATCH-YYYYMMDD-HHMMSS-XXXXX` на всю группу.
4. `pricing_model = PaymentProviderManager::pricingModelFor(driver)` (`bpa_v2` / `legacy_flat10`) фиксируется на заказе и больше не меняется: от неё зависят комиссия, база выплаты и драйвер оплаты (`forNewBatch` читает её с заказа).
5. Для каждого продавца создаётся отдельный `Order`:
   - `subtotal = Σ(price × qty)`, `delivery_cost` серверная, `fee_amount = Order::calculatePlatformFeeFor(subtotal, pricing_model)` (в `bpa_v2` — по карточной ставке как максимальной, уточняется при инициации платежа), `total_amount`.
   - `customer_name/phone/email`, `delivery_service`, `payment_batch_id`, `source='platform'`, статусы `PENDING`.
   - `OrderItem` с `product_snapshot`, атомарный резерв склада (`decreaseStockAtomically`).
   - `OrderAddress` (ПВЗ: `pickup_point_id/name/data`, извлечение `postal_code`; или курьер: `city`, `address_line1`).
   - `OrderShipment` (`carrier`, `delivery_method`, `cost`, `weight` по весу позиций).
   - запись `OrderStatusHistory` (создан).
6. Уведомления `OrderCreatedForBuyer` / `OrderCreatedForSeller`.
7. Возврат `{ orders, payment_batch_id, notices }` → фронт инициирует [оплату](/processes/payments-moneta).

::: warning Один путь создания заказов
Второго пути быть не должно. До 05.09.2026 рядом жил дубль `createOrdersFromCart()`: выбор драйвера и фискальный гейт были встроены только в него, контроллер его не звал, и заказы получали легаси-модель денег — на проде оплата уходила в историческую схему МОНЕТЫ (ЛК1 без пароля) вместо кассы агрегатора. Дубль удалён; тесты чекаута обязаны ходить через `createMultipleOrders` или `POST /api/orders/checkout`.
:::

## Доставка на этапе оформления: `DeliveryService`

`app/Services/Order/DeliveryService.php` оркестрирует провайдеров:

- `calculateDeliveryCost($carrier, $from, $to, $weight, ...)` / `calculateAllCarriers(...)` — расчёт по одному или всем.
- `getPickupPoints($city)` / `getPickupPointsByCoordinates($lat,$lon)` (радиус ≤50км) / `getPickupPointsByBounds(bbox)` — три режима поиска ПВЗ; кеш 1–24ч.
- Провайдеры: `CdekProvider` (тариф **136** — ПВЗ→ПВЗ; требует `postal_code`; каталог ПВЗ в `CdekPickupPoint`), `RussianPostProvider` (ОПС, расчёт, оформление, PDF-накладная). Прочие перевозчики — stub (`DeliveryStubData`).

**DaData** (`Api\DaDataController`): `POST /api/dadata/suggest/{address,streets,cities}`, `POST /api/dadata/clean/address`, `GET /api/dadata/postal-unit/suggest` — подсказки/стандартизация адресов (throttle 60/мин).

## Frontend

| Файл | Роль |
|---|---|
| `nuxt/stores/cart.ts` | стор корзины; `deselectedItemIds` (по умолчанию выбрано всё), `selectedItemsBySeller`, `merge()`, `selectOnly()` |
| `nuxt/pages/cart.vue` | страница корзины, галочки выбора |
| `nuxt/pages/checkout.vue` | оформление: блок на продавца, доставка, получатель, оплата |
| `nuxt/components/checkout/*` | `CheckoutOrderBlock`, `CheckoutRecipientForm`, `CheckoutInlineRegister` (гость), `PaymentMethodSelector`, `CheckoutOrderSummary`/`CheckoutMobileBottomBar` |

`handleProceedToPayment()` собирает `deliveryBySeller` + `recipientData` → `POST /orders/checkout` → инициация платежа.

## Что делать, если пошло не так

| Ситуация | Поведение | Кто чинит |
|---|---|---|
| Товар кончился между добавлением и checkout | `is_available=false`, серая секция «Больше не в наличии», исключён из выбора | покупатель (убирает) |
| Пустой выбор при переходе к оплате | guard `hasSelectedItems` + редирект | автоматически (фронт) |
| ПВЗ без индекса | `postal_code` резолвится из `pickup_point_data` / id `rp-XXXXX` | автоматически (`CheckoutService`) |
| Расчёт перевозчика недоступен | fallback на stub-данные (кроме реального API Почты) | автоматически |
| Продавец без фискальных реквизитов при включённой кассе (`bpa`) | `422` + issue `seller_not_fiscal_ready`, заказ не создан; в логе `Checkout: продавец не готов к фискализации` с перечнем `missing` | продавец / админ (реквизиты в НКО) |

## Как тестировать

**Приоритет P0** (сейчас **0 автотестов** у Cart и Checkout — критический пробел):

1. 2–3 товара от разных продавцов → checkout → заказы разделяются по продавцам, общий `payment_batch_id`.
2. Изменение количества/удаление в корзине → пересчёт summary.
3. ПВЗ: выбор пункта выдачи → корректный `postal_code` и стоимость.
4. Почта России: реальный расчёт стоимости/срока.
5. Курьер: обязателен адрес (`courier_address`), иначе валидация.
6. Гость: инлайн-регистрация в checkout + merge гостевой корзины.
7. Расчёт `platform_fee` и `total_amount` совпадает между `/calculate` и `/checkout`.

**Покрытие:** нет (см. [матрицу покрытия](/testing/coverage-matrix)) — приоритетная цель этапа автотестов: `CartController`, `CheckoutController`.

## Ключевые файлы

| Область | Файл |
|---|---|
| Корзина | `app/Http/Controllers/Api/CartController.php`, `app/Models/CartItem.php`, `app/Http/Requests/Cart/*` |
| Checkout | `app/Http/Controllers/Api/Orders/CheckoutController.php`, `app/Services/Order/CheckoutService.php`, `app/Http/Requests/Order/{CalculateOrderRequest,CreateOrdersRequest}.php` |
| Доставка | `app/Http/Controllers/Api/Orders/DeliveryController.php`, `app/Services/Order/DeliveryService.php`, `app/Services/Delivery/{CdekProvider,RussianPostProvider,DeliveryStubData}.php` |
| DaData | `app/Http/Controllers/Api/DaDataController.php`, `app/Services/DaDataService.php` |
| Frontend | `nuxt/stores/cart.ts`, `nuxt/pages/{cart,checkout}.vue`, `nuxt/components/checkout/*` |
| Модели | `app/Models/Order/{Order,OrderItem,OrderAddress,OrderShipment}.php` |
