# Доставка (СДЭК / Почта России)

> Приоритет: **P1**. Актуально на 2026-07-05.

## Назначение

Расчёт стоимости/сроков, поиск ПВЗ, оформление отправления, накладная/QR и трекинг. Два реальных провайдера — СДЭК (ПВЗ→ПВЗ, тариф 136) и Почта России (Otpravka API); прочие перевозчики — stub. Трекинг — поллингом (не вебхуками).

## Endpoints

| Метод | Путь | Контроллер | Назначение |
|---|---|---|---|
| `POST` | `/api/orders/delivery/calculate` | `Api\Orders\DeliveryController::calculate` | Стоимость (один/все перевозчики) |
| `GET` | `/api/orders/delivery/pickup-points` | `pickupPoints()` | ПВЗ по городу / координатам / bbox |
| `GET` | `/api/orders/delivery/courier-options` | `courierOptions()` | Курьерские опции |
| `POST` | `/api/orders/delivery/track` | `track()` | Трекинг |

Создание отправления — по событию `OrderSellerConfirmed` (см. [жизненный цикл](/processes/order-lifecycle)).

## Трекинг

`CheckDeliveryStatus` опрашивает перевозчиков каждые 6 часов и двигает вместе с доставкой статус заказа: прибытие в пункт выдачи → `DELIVERED` («Доставлен»), вручение → `COMPLETED` («Завершён»). Метка `delivered_at` ставится только по факту вручения и берётся из даты события перевозчика — от неё считаются срок возврата и окно выплаты.

**Порядок статусов СДЭК обратный:** `entity.statuses` приходит от новых к старым. Актуальным считается элемент с максимальной `date_time` (`CdekProvider::trackShipment`), а не последний в массиве — на этом уже был баг, из-за которого заказ навсегда оставался в «Отправлено».

Незнакомый код статуса трактуется как «в пути» и пишет в лог `CDEK: неизвестный код статуса` — по этим записям пополняется маппинг `CdekProvider::mapCdekStatus`.

Дожать конкретный заказ вручную: `php artisan delivery:advance {id или полный номер заказа}`.

## Как тестировать

**Покрытие:** 🟡 7 (`tests/Feature/Delivery/CdekIntegrationTest.php`). Пробел: ПВЗ (частично), курьеры, реальный e2e с sandbox (прод-креды СДЭК не заведены). См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Оркестратор | `app/Services/Order/DeliveryService.php` |
| Провайдеры | `app/Services/Delivery/{CdekProvider,RussianPostProvider,DeliveryStubData}.php` |
| Джобы | `app/Jobs/{CheckDeliveryStatus,RefreshPendingCdekShipments}.php` |
| Модели | `app/Models/Order/{OrderShipment,OrderAddress}.php`, `app/Models/{SellerPickupPoint,CdekPickupPoint}.php` |
| Интеграции | CDEK API v2 (`config/services.cdek`), Почта Otpravka (`config/services.russian_post`) |

