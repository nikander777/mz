# Флоу продавца: данные, выплаты, договор с НКО

> Каноничный документ по жизненному циклу продавца MUZILLA: кто что заполняет,
> куда летят данные, как устроены выплаты и что делать, если что-то пошло не так.
> Актуально на 2026-09-29.

## Содержание

1. [Действующие лица](#действующие-лица)
2. [Где что хранится](#где-что-хранится)
3. [Обзор жизненного цикла](#обзор-жизненного-цикла)
4. [Этап 1. Регистрация продавца](#этап-1-регистрация-продавца)
5. [Этап 2. Витрина](#этап-2-витрина)
6. [Этап 3a. Подключение выплат — физлицо](#этап-3a-подключение-выплат--физлицо-individual)
7. [Этап 3b. Подключение выплат — ЮЛ/ИП](#этап-3b-подключение-выплат--юл--ип)
8. [Этап 4. Заказ → оплата](#этап-4-заказ--оплата-деньги-сразу-на-счёте-продавца)
9. [Этап 5. Окно удержания](#этап-5-окно-удержания)
10. [Этап 6. Счёт продавца, история и вывод](#этап-6-счёт-продавца-история-и-вывод)
11. [Сверка денег продавцов](#сверка-денег-продавцов)
12. [Статусы и блокировка](#статусы-и-блокировка)
13. [Что делать, если что-то пошло не так](#что-делать-если-что-то-пошло-не-так)
14. [Инструменты поддержки](#инструменты-поддержки)
15. [Ключевые файлы](#ключевые-файлы)

---

## Действующие лица

| Актор | Роль |
|---|---|
| **Продавец** | Заполняет профиль, реквизиты выплат, подписывает оферту |
| **Покупатель** | Оплачивает заказ, подтверждает получение |
| **Платформа** (Laravel `main`) | Хранит данные, оркестрирует онбординг, держит срок удержания, ведёт учёт по счёту продавца, инициирует вывод |
| **НКО МОНЕТА / касса ПА** | Платёжный провайдер: регистрация ЮЛ/ИП, договор, счета 40821, расщепление платежа на счета получателей, возвраты |
| **DaData** | Автозаполнение по ИНН из ЕГРЮЛ/ЕГРИП |
| **Поддержка** (админка) | Ручное управление онбордингом через `Admin\MonetaSellerController` |

## Где что хранится

| Таблица | Что лежит |
|---|---|
| `users` | ФИО, `username`, `city`, `email`, `phone`, `is_seller`, `registration_type`, аватар + **витрина**: `description`, `contacts`, `delivery_payment`, `standard_description`, `auto_message` |
| `seller_profiles` | **Идентификация:** `legal_form`, `inn`, `company_name`, `company_legal_form`, `kpp`, `ogrn`, `ogrnip`, `legal_address`, `jurisdiction`, `date_of_birth` · **НКО:** `moneta_unit_id`, `moneta_account_id`, `moneta_contract_status`, `agreement_signed_at`, `agreement_doc_path`, `moneta_synced_at` · **ФЛ-выплаты:** `payout_method`, `payout_card_token` (🔒hidden), `payout_card_mask`, `payout_sbp_phone`, `payout_sbp_bank_id`, `self_employed_confirmed_at` · **Анкета:** `payout_setup_data` (🔒AES-encrypted: паспорт, банк, согласия) |
| `orders` | `moneta_operation_id`, `payout_eligible_at` (конец окна удержания), `seller_payout_status` (`settled_on_account` = окно закрыто), `seller_payout_amount`, `seller_payout_at` |
| `seller_profiles` (счёт) | `reserve_balance` (остаток счёта в НКО, кэш), `reserve_required` (неснижаемый остаток, NULL = дефолт 2000 ₽), `debt_balance`, `balance_synced_at`, `statement_synced_at`, `statement_sync_error`, `balance_mismatch`/`_since` |
| `seller_ledger_entries` | История счёта: `source=statement` — операции выписки НКО (зачисление товара/доставки, комиссия, возврат, вывод, прочее), `source=platform` — учёт площадки (долг, корректировки). Уникальность `(moneta_operation_id, type)` |
| `seller_withdrawals` | Заявки на вывод: `pending → processing → succeeded / failed`, `client_transaction`, номер операции НКО |

> 🔒 `payout_card_token` и `payout_setup_data` — в `$hidden` модели, наружу через API не отдаются.
> `payout_setup_data` шифруется AES-256 через `APP_KEY` (cast `encrypted:array`).

## Обзор жизненного цикла

```
Регистрация (разово: ФИО, юр.форма, реквизиты компании)
   → Витрина (описание/контакты/доставка) — редактируется всегда
   → Публикация хотя бы одного лота
   → ⛔ ГЕЙТ: без опубликованного лота форма подключения выплат закрыта
   → Подключение выплат (ЮЛ/ИП: онбординг в НКО + договор)
   → ⛔ ГЕЙТ: пока анкету не одобрила НКО, лоты продавца НЕ ВИДНЫ в каталоге
   → Заказ → оплата → агрегатор сразу расщепляет платёж:
        товар — на счёт 40821 продавца, доставка — на счёт площадки
   → Окно удержания (17 дней от вручения / 24 от отправки) → деньги доступны к выводу
   → Вывод со счёта 40821 на реквизиты — только через ЛК Muzilla (пока выключен)
```

Заводить лоты продавец может сразу после регистрации — ждать одобрения
с пустым кабинетом не нужно. Невидимы они только для покупателей.

**Первый лот — предусловие онбординга, а не следствие.** НКО МОНЕТА активирует
юнит, только убедившись, что на странице магазина размещён товар: в анкету
уходит ссылка на витрину конкретного продавца
(`MonetaMerchantApiService::shopUrl` → `MONETA_SITE_URL` + `/u/{slug}`), и
проверяющий открывает именно её. Поэтому:

- `GET payout-setup/status` отдаёт `has_published_product` и
  `published_products_count` (критерий — `products.status = active`);
- `start`, `submit-all` и `accept-conditions` без единого опубликованного лота
  отвечают **422** (`PayoutSetupController::assertHasPublishedProduct`);
- на странице `/seller/payout-setup` вместо формы анкеты показывается заглушка
  со ссылкой на создание лота;
- сквозной баннер продавца (`SellerSaleBlockedBanner`) первым пунктом чек-листа
  показывает «опубликуйте хотя бы один товар» — признак приходит в
  `/api/auth/me` как `product_setup.has_published`.

---

## Этап 1. Регистрация продавца

**Кто:** новый пользователь (`/seller/register`) или существующий покупатель («Стать продавцом»).
**Endpoint:** `POST /api/auth/register/seller` (`registerSeller`) или `POST /api/auth/become-seller` (`becomeSeller`).
**Валидация:** `SellerRegistrationRequest` / `BecomeSellerRequest`.

```
Продавец ──(ФИО, юр.форма, [ИНН/наименование/ОГРН/КПП/адрес для ЮЛ/ИП])──▶ Платформа
   Платформа: users (ФИО, is_seller=true, registration_type)
              seller_profiles (legal_form + реквизиты компании — РАЗОВО)
```

Что собирается:
- **Всегда:** `first/last/middle_name`, `username`, `city`, `legal_form`, `jurisdiction`, `date_of_birth`.
- **ЮЛ/ИП:** `company_name`, `inn` (10/12 цифр), `legal_address`; **ЮЛ** ещё `kpp`+`ogrn`, **ИП** — `ogrnip`.

> Выписка ЕГРЮЛ/ЕГРИП **больше не собирается** (НКО получает данные по ИНН через СМЭВ).

Это **единственный разовый ввод** реквизитов компании. Дальше они read-only — правка только через payout-setup (этап 3b), а блок «Данные о компании» на `/seller` показывает их как read-only зеркало.

## Этап 2. Витрина

**Кто:** продавец в ЛК `/seller`.
**Endpoint:** `POST /api/profile/seller/info/update` (`updateInfo`).
**Данные → `users`:** `description`, `contacts`, `delivery_payment`, `standard_description`, `auto_message`.

```
Продавец ──(описание/контакты/доставка/автосообщение)──▶ users  (редактируется ВСЕГДА)
```

Личные данные (ФИО/город/никнейм) редактируются в профиле покупателя `POST /api/profile/update` — на странице продавца их нет (убрали дубли).

### Гейт каталога: товары видны только после одобрения анкеты НКО

Лот попадает в выдачу, только когда у продавца **одновременно**:

| Признак | Откуда берётся |
|---|---|
| `seller_profiles.moneta_contract_status = active` | коллбек НКО `EDIT_CONTRACT` (юнит переведён в группу «Активные клиенты») |
| `seller_profiles.moneta_account_id` заполнен | коллбек `EDIT_ACCOUNT` / `MonetaAccountProvisioner` (расширенный счёт получателя) |

Оба признака сводятся в `SellerProfile::isMonetaActive()`, оттуда — в
`SellerProfile::isBlocked()` → `User::canSell()` → денормализованный
`users.can_sell` → `seller_can_sell` в документе Meili. Пересчёт происходит
автоматически хуком `SellerProfile::booted()` при любом изменении статуса
договора или счёта, включая приход коллбека.

Почему так: до одобрения агрегатору **некуда переводить долю продавца** —
расщепление платежа адресуется его счётом в НКО. Витрина с такими лотами вела
бы покупателя в тупик на чекауте.

Продавец без `seller_profile` (мигрированные аккаунты легаси-портала) гейт не
проходит: анкету он не подавал, значит и одобрения быть не может.

#### Исключение: превью лотов на странице магазина

Гейт каталога закрыл бы и страницу самого магазина — а именно её проверяет НКО,
и получился бы замкнутый круг (НКО ждёт товар на витрине, витрина ждёт НКО).
Поэтому `GET /api/public/products?seller_id=X` для продавца, который ещё не
допущен к продажам, отдаёт **превью**: до `SellerShopPreview::LIMIT` (12)
активных лотов обычным SQL-запросом мимо Meili, без поиска, сортировки и
пагинации; в ответе появляется блок `shop_preview: {limit, total}`, по которому
фронт рисует плашку «магазин проходит проверку» и прячет лишние контролы.

Кому показывается (`SellerShopPreview::applies`): активный незаблокированный
продавец-ЮЛ/ИП с `can_sell = false`, не отклонённый админом и не заблокированный
НКО. Поданное заявление НЕ требуется — витрину нужно видеть до отправки анкеты.

Что при этом **не меняется**: состав индекса Meili и фильтры каталога. В каталог,
поиск и фасеты такие лоты по-прежнему не попадают — режет `seller_can_sell`.

Карточка товара такого продавца открывается (`ProductsController::show` пускает
её вместо 404 — проверяющий кликает по превью), но заказ закрыт:
`ProductResource.orderable = false` гасит кнопку, `CartItemPolicy::create`
отбивает добавление в корзину, `CheckoutService` — оформление заказа
(`seller_cannot_sell`).

**Рубильник аварийного отката** — `MZ_REQUIRE_MONETA_APPROVAL=false`
(`config/marketplace.php` → `seller_gate.require_moneta_approval`). Возвращает
в каталог всех, включая тех, кому платёж провести некуда. После смены значения
обязательно:

```bash
php artisan sellers:init-verification --dry-run   # кого затронет
php artisan sellers:init-verification             # пересчёт users.can_sell
php artisan products:meili-index                  # синхронизация индекса
```

---

## Этап 3a. Подключение выплат — физлицо (`individual`)

ФЛ **не регистрируется в НКО**. Просто указывает, куда выводить деньги (C2C). Страница `/seller/payout-setup`.

### Вариант «Карта»
```
1. Продавец ──POST payout-setup/individual {payout_method:'card', self_employed}──▶ seller_profiles
2. Продавец ──POST payout-setup/card-binding/init──▶ Платформа
                Платформа ──createCardBindingPayment──▶ МОНЕТА ──payment_url──▶ Продавец
3. Продавец вводит карту на стороне МОНЕТА
4. МОНЕТА ──webhook (MNT_CARD_TOKEN + MNT_CARD_MASK)──▶ PaymentService::handleSellerCardBindingWebhook
                → seller_profiles.payout_card_token (🔒) + payout_card_mask
```

### Вариант «СБП»
```
Продавец ──POST payout-setup/sbp {phone:+7…, bank_id}──▶ seller_profiles.payout_sbp_phone + payout_sbp_bank_id
   (bank_id из GET payout-setup/sbp-banks → config/sbp_banks.php)
```

**Статус:** как только карта-токен (или СБП телефон+банк) заполнены → `PayoutSetupStatus = active`.

**Самообслуживание (важно):** для ФЛ `editable = true` **всегда**, в т.ч. в `active`. Карту/СБП можно перепривязать в любой момент — это не договор с НКО, а самообслуживаемые реквизиты. (Контролируется `PayoutSetupController::isProfileEditable`.)

**54-ФЗ:** галочка «самозанятый» → `self_employed_confirmed_at`.

## Этап 3b. Подключение выплат — ЮЛ / ИП

Полноценная регистрация юнита в НКО МОНЕТА + подписание договора. Оркестратор — `POST payout-setup/submit-all` (или пошагово отдельными ручками).

### Шаг 0 — автозаполнение
```
Продавец вводит ИНН → GET payout-setup/suggest-by-inn ──▶ DaData (ЕГРЮЛ)
   ◀── наименование, КПП, ОГРН, юр.адрес, ФИО руководителя  → подставляются в форму
```

### Шаг 0.5 — налоговые данные продавца

В анкете два поля, которые нужны **не НКО, а кассе агрегатора**:

| Поле формы | Куда попадает | Зачем |
|---|---|---|
| «Система налогообложения» (обязательное: ОСНО/УСН/ПСН/НПД) | `seller_profiles.tax_regime` | из режима выводится ставка НДС |
| «Ставка НДС» (необязательное: 22/10/5/7/0/без НДС/расчётные) | `seller_profiles.default_vat_code` | явное значение перебивает выведенное — у ОСНО бывают льготные ставки, на УСН с доходом выше порога НДС 5 %/7 % |

Из режима выводится: ОСНО → 22 % (1113, с 01.01.2026), УСН/ПСН/НПД → без НДС (1105).
НДС 5 %/7 % на УСН из режима не выводится — только явной ставкой.

Коды ставок агрегатора (`vatTag`/`productVatCode`) — из «Описания взаимодействия с
сервисом kassa.payanyway.ru», ред. 2.5 от 15.12.2025
([PDF](https://www.payanyway.ru/info/p/ru/public/merchants/Assistant54FZ.pdf); 5 %/7 %
добавлены в ред. 2.4 от 27.12.2024, 22 % — в ред. 2.5). Перечень в коде — `SellerFiscalReadiness::VAT_CODES`,
подписи — `nuxt/utils/sellerTax.ts`:

| Код | Ставка | Код | Ставка |
|---|---|---|---|
| 1113 | 22 % | 1114 | расчётная 22/122 |
| 1103 | 10 % | 1107 | расчётная 10/110 |
| 1108 | 5 % (УСН) | 1110 | расчётная 5/105 |
| 1109 | 7 % (УСН) | 1111 | расчётная 7/107 |
| 1104 | 0 % | 1105 | без НДС |
| 1102 | 20 % (до 2026) | 1106 | расчётная 20/120 (до 2026) |

Кода 1112 в перечне нет. Страница мультикорзины BPA в docs.moneta.ru
(`/54-fz/bpa-pa-paw/multi-basket/paw-receipt/create-invoice/`) до сих пор перечисляет
только 1102–1107 — она устарела относительно кассы; первый живой счёт с новым кодом
стоит проверить по чеку.

Резолв ставки на позицию чека:
`order_items.vat_code` ← `products.vat_code` ?? `seller_profiles.default_vat_code`
?? `payments.fiscal.default_vat_code`. Снапшот снимается **один раз, при первом
выставлении счёта** (`OrderItemFiscalSnapshot`, зовётся из `InventoryBuilder`)
вместе с `order_items.fiscal_name`; до этого в колонке NULL. Дальше ставка уходит
агрегатору полем `productVatCode` строки номенклатуры `/api/invoice` — именно по
нему ККТ агрегатора пробивает чек **от имени продавца**. Подтверждение и чек
возврата берут ставку и название из позиции, а не пересчитывают: смена режима
продавца или правил санитизации после оплаты чек не меняет.

После подачи анкеты в НКО форма выплат у продавца read-only, и сменить режим или
ставку он сам не может. Это делает поддержка из админки: карточка продавца →
блок «Налогообложение» → `PATCH /api/admin/sellers/{sellerProfile}/tax`
(право `sellers.edit`, есть у admin/super-admin). Ручка хранит ставку
разрезолвленной, правит сохранённый payload анкеты (prefill формы продавца) и
пишет запись в журнал действий. Действует только на позиции, по которым счёт
ещё не выставлялся — см. снапшот выше.

> ⚠️ **В профиль НКО налоговые данные не передаются — их там нет.**
> Проверено живьём на demo.moneta.ru 31.08.2026: `CheckProfile` для ЮЛ/ИП
> перечисляет только скоупы Personal / Director / Juridical / Bank, а
> `EditProfile` с ключами `TAX_SYSTEM`, `TAXATION_SYSTEM`, `SNO`, `VAT`, `NDS`
> отвечает «Ошибочные (нераспознанные) поля в запросе нужно удалить» и
> отбивает **весь** запрос. На случай, если НКО заведёт такие атрибуты,
> оставлены пустые `MONETA_ATTR_TAX_REGIME` / `MONETA_ATTR_VAT_CODE`:
> заполненное имя ключа включает отправку, пустое — нет.

### Шаг 1 — создание юнита
```
Продавец ──submit-all {legal_form, inn, company_name, контакты, директор, паспорт, банк, согласия}──▶ Платформа
   Платформа ──createProfile (INN, ORGANIZATION_NAME_SHORT, CONTACT_EMAIL, URL)──▶ МОНЕТА
   ◀── unitId  → seller_profiles.moneta_unit_id, contract_status=registered
```

`URL` — ссылка на страницу магазина (`MONETA_SITE_URL` + `/u/{slug}`, у продавца
без slug — `/u/{id}`), по ней НКО проверяет размещённый товар. Схема строго
`http://`: `https` МОНЕТА в этом поле не принимает.

### Шаг 2 — заполнение скоупов (внутри submit-all либо отдельными ручками)
```
fill-personal   → контакты, согласия, ФИО подписанта, обороты, капитал (ЮЛ)
fill-director   → ИНН физлица, ДР, адреса, резидент РФ
attach-bank     → расчётный счёт + БИК (проверка контрольной суммы по алгоритму ЦБ)
attach-passport → серия/номер/дата выдачи/кем выдан
                                 ▼
   Полная анкета шифруется → seller_profiles.payout_setup_data (🔒 паспорт+счёт наружу не отдаются)
   В МОНЕТА улетают соответствующие scope-атрибуты
```

### Шаг 3 — акцепт условий → активация
```
accept-conditions (CONDITIONS_CORRECT_DATA=Y) ──▶ МОНЕТА
   Платформа диспатчит ActivateMonetaUnitJob (очередь)
```

### Шаг 4 — оферта (договор)
```
МОНЕТА формирует персональное «Заявление о присоединении»
Продавец ──GET payout-setup/agreement/partner-application──▶ скачивает PDF
Продавец подписывает (бумага / ЭЦП Диадок) и отправляет ОРИГИНАЛ в НКО
Продавец ──POST payout-setup/agreement/upload (копия PDF)──▶ seller_profiles.agreement_doc_path + agreement_signed_at
   → статус verifying.  ⏳ заявление должно дойти в НКО за 30 дней, иначе blocked.
```

### Шаг 5 — НКО активирует (асинхронно, webhook)
```
НКО проверяет → МОНЕТА ──webhook EDIT_CONTRACT (status=ACTIVE)──▶ MonetaMerchantWebhookController
   → seller_profiles.moneta_contract_status = active
   → Платформа ──createAccount(unitId, type=2, subTypeId=50)──▶ МОНЕТА ◀── accountId
   → seller_profiles.moneta_account_id = accountId
   → статус active  ✅ можно получать выплаты
```

`ReconcileMonetaContractsJob` периодически досинхронизирует статусы, если webhook потерялся.

> ⚠️ **Счёт получателя = «40821» (05.09.2026).** В схеме кассы ПА деньги продавцу переводятся
> на счёт, который юридически принадлежит агенту, — в MerchantAPI это расширенный счёт
> (`type=2`) с подтипом **50 «Агентский»** (`subTypeId`). Обычный расширенный счёт без подтипа
> НКО как получателя не приняла («необходимо создать счёт 40821»). Подтип задаётся через
> `MONETA_ACCOUNT_SUBTYPE=50` (прод); на demo, где подтип не включён, переменная пустая.
> У ООО «М9» (unit 23103583) рабочий счёт — 78341566, он же `PAYMENTS_PLATFORM_ACCOUNT`
> для строки доставки; 81090786 создан без подтипа и подлежит закрытию НКО.

> ⚠️ **Открытый пробел (31.08.2026).** `CheckProfile` на demo просит для ИП ещё
> два блока, которых `submit-all` не заполняет:
> - scope **Juridical**, метод `CreateLegalInformation` — `OKVED`, `OGRNIP`, `OKPO`;
> - в scope **Personal** — `REGISTRATION_DATE_RU` и `LEGAL_ADDRESS`.
>
> Пока они не отправляются, `CheckProfile` остаётся в `DATA_REQUIRED`,
> `CONDITIONS_CORRECT_DATA` не выставляется, юнит не переводится в «Активные
> клиенты» — и продавец не проходит гейт каталога. Для ЮЛ часть этих полей
> может подтянуть СМЭВ по ИНН; для ИП — нет.

---

## Этап 4. Заказ → оплата (деньги сразу на счёте продавца)

Касса платёжного агрегатора (драйвер `bpa`, прод с 31.08.2026) **расщепляет платёж
сама** — транзитного счёта платформы, с которого потом «выплачивают», в этой схеме нет.

```
Покупатель оплачивает заказ (СБП — сразу; карта — холд, списание при приёмке посылки СДЭК)
   → агрегатор создаёт по операции зачисления на каждую строку счёта:
        MZ{order}I{item} — товар  → на счёт 40821 продавца (moneta_account_id),
                                    за вычетом комиссии (маржа площадки + эквайринг + фискализация)
        MZ{order}D       — доставка → на счёт площадки (PAYMENTS_PLATFORM_ACCOUNT),
                                    за вычетом эквайринга
   → orders.moneta_operation_id = операция оплаты (родитель зачислений)
```

> ⚠️ **Счёт площадки = счёт продавца ООО «М9»** (78341566, магазин team@muzilla.ru).
> Отдельного счёта под доставку не будет (решение 29.09.2026), поэтому в истории М9
> видны доставки **всех** заказов маркетплейса — строкой «Оплата доставки · Доставка ·
> Заказ N», а по своим заказам М9 — и товар, и доставка.

Возврат идёт обратным путём: `RefundRequest` по операциям **зачисления** — со счёта
продавца (товар) и со счёта площадки (доставка). Агрегатор списывает полную сумму строки,
а зачислено было за вычетом комиссии, — разница (комиссия) при отмене теряется
получателем. Кто её несёт — открытый вопрос владельца (29.09.2026).

## Этап 5. Окно удержания

Деньги уже на счёте продавца, но **к выводу закрыты**, пока покупатель может вернуть
товар или открыть спор: `payout_eligible_at = min(shipped_at + 24д, delivered_at + 17д)`.

```
ReleaseDeliveredOrders (ежечасно): окно истекло, спора и активного возврата нет,
                                   доставка не returned/cancelled/error
   → InitiateSellerPayout → PayoutService::initiateSellerPayout
        касса агрегатора → SellerSettlementService::settleOrder:
            seller_payout_status = settled_on_account («окно закрыто»),
            seller_payout_amount = фактически зачисленное по выписке (без выписки — расчётное)
            проводок НЕ пишет: движение денег уже в истории из выписки
        историческая схема (moneta) → перевод с транзита, как раньше
   → письмо продавцу «Средства по заказу № … больше не удерживаются»
```

Посылка, которую СДЭК вернул (`NOT_DELIVERED` «Не вручен» → `delivery_status=returned`),
окно не закрывает никогда: выплата по ней заблокирована, а сверка поднимает заказ как
«деньги покупателю не возвращены».

## Этап 6. Счёт продавца, история и вывод

Раздел «Финансы» (`/seller/finances`) и «Счёт и вывод средств» (`/seller/balance`).

**Остаток и история из одного источника.** «На счёте» — остаток счёта 40821 из НКО
(`FindAccountById`), «История операций» — выписка того же счёта (`FindOperationsList`),
перенесённая в `seller_ledger_entries`. Сумма проводок выписки **равна** остатку — это
главное равенство раздела; расхождение фиксируется на профиле и уходит в сверку.

| Операция выписки | Проводки в истории |
|---|---|
| Зачисление товара `MZ{order}I{item}` | «Продажа» (полная сумма строки, позиция = название товара) + «Комиссия площадки» |
| Зачисление доставки `MZ{order}D` | «Оплата доставки» (позиция «Доставка») + «Комиссия эквайринга за доставку» |
| Возврат (`isrefund`) | «Возврат покупателю» — заказ и позиция от операции зачисления, которую он возвращает |
| Списание по нашей заявке на вывод | «Вывод средств» |
| Всё остальное | «Операция по счёту» без заказа — попадает в сверку |

Плюс проводки площадки, которых в НКО нет: обратная доставка, перевыставленная комиссия
агента (долг продавца) и ручные корректировки администратора.

**Когда история обновляется:** ежечасно по всем счетам (`ReconcileSellerBalances`) и через
`payments.statement.sync_delay_seconds` (180 с) после оплаты, отправки и возврата по заказу
(`SyncSellerAccount`, слушатель `SyncSellerAccountsOnMoneyEvent`). Выписка берётся с
перекрытием 48 ч от прошлой синхронизации (операции НКО проводит не мгновенно), перенос
идемпотентен. Лимит НКО — период запроса не длиннее 30 дней, клиент режет на окна.

**Доступно к выводу:**

```
доступно = остаток − неснижаемый остаток (2000 ₽) − долг − ожидает срока − вывод в обработке
```

- **Ожидает срока** — сумма проводок выписки по заказам, окно которых не закрыто
  (`seller_payout_status` не `settled_on_account`/`completed`), включая отменённые, но не
  возвращённые: это деньги покупателя;
- **Вывод в обработке** — заявки `pending`/`processing` и успешные, которые остаток НКО
  ещё не отразил (завершены после `balance_synced_at`).

**Вывод средств.** `POST /api/profile/seller/balance/withdraw` → `SellerWithdrawalService`:
под блокировкой строки профиля проверяет доступное и заводит заявку `pending`, затем
**вне транзакции БД** обращается к НКО (`SellerWithdrawalTransport`): ответ → `succeeded`
/ `failed`, неясный исход (таймаут) → заявка остаётся `processing`, сумма — вычтенной
(повторять перевод нельзя). Проводку списания приносит выписка.

> ⚠️ **Вывод выключен** (`PAYMENTS_WITHDRAWAL_ENABLED=false`), транспорт не реализован
> (`UnconfiguredWithdrawalTransport` отказывает явно). По документации НКО площадка
> управляет счетами клиентов запросом MerchantAPI `PaymentRequest`, но формат, пароль
> подписи, комиссию и сроки НКО выдаёт под проект — их нужно запросить. Открыт и вопрос,
> может ли продавец вывести деньги сам из кабинета МОНЕТЫ: если да, удержание площадки
> не работает.

## Сверка денег продавцов

`SellerFinanceAnomalies` (админка «Финансы», бейдж «Требует внимания», дайджест
`ReportSellerFinanceAnomalies` раз в 6 ч супер-админам и админам при изменении состава):

| Тип | Что значит | Живой пример |
|---|---|---|
| `cancelled_not_refunded` | заказ отменён, по выписке деньги остались на счетах | 2993 (возврат упал 08.09) |
| `payment_not_recorded` | зачисление по заказу есть, а оплата в заказе не проведена | 2956 (`payment_status=processing`) |
| `unmatched_operation` | операция по счёту без заказа | — |
| `balance_mismatch` | остаток НКО ≠ сумма выписки дольше 2 ч | — |
| `sync_failed` / `sync_stale` | выписка не грузится / не обновлялась дольше 3 ч | VM-2 без `MONETA_*` (09.09) |
| `undelivered_not_refunded` | посылка вернулась, деньги покупателю не возвращены | 2999 |
| `withdrawal_stuck` | заявка на вывод без ответа НКО дольше 30 мин | — |

---

## Статусы и блокировка

`PayoutSetupStatus` (вычисляется по полям `seller_profiles`, не хранится):

| Статус | Значение | ЮЛ/ИП редактируемо? | ФЛ редактируемо? |
|---|---|---|---|
| `not_started` | Не начато | ✅ | ✅ |
| `filling` | Идёт заполнение | ✅ | ✅ |
| `agreement_required` | Нужно подписать оферту | 🔒 нет | — (нет у ФЛ) |
| `verifying` | Ждём проверки НКО | 🔒 нет | — (нет у ФЛ) |
| `active` | Активен / реквизиты сохранены | 🔒 нет | ✅ **да** |
| `blocked` | НКО заблокировала | ✅* | — (нет у ФЛ) |

🔒 = `isProfileEditable=false`: фронт блокирует ввод, бэкенд возвращает **403**, изменение — только через поддержку.

**Принцип:** контрактные данные ЮЛ/ИП после старта оформления договора — предмет подписанного «Заявления о присоединении», менять в одностороннем порядке нельзя. ФЛ-выплаты (карта/СБП) договором не являются → самообслуживание всегда.

\* `blocked` для ЮЛ/ИП формально остаётся editable (можно перезаполнить после разблокировки).

---

## Что делать, если что-то пошло не так

| # | Ситуация | Поведение системы | Кто и как чинит |
|---|---|---|---|
| 1 | Опечатка в ИНН/наименовании **до** оформления (`not_started`/`filling`) | Поля редактируемы | Продавец сам — на «Подключение выплат» |
| 2 | Опечатка обнаружена **после** отправки/активации (`verifying`/`active`) | 403 на запись | Продавец подаёт **заявку на изменение** (см. ниже); после согласования данные вносит **поддержка** (`MonetaSellerController`): `check` → `fill-*`/`attach-*`; при сильном расхождении — `register` заново |
| 3 | Смена юр.формы (ФЛ↔ИП↔ЮЛ) | Read-only (мы закрыли «тихую» смену) | **Поддержка**: новая регистрация юнита + новое заявление |
| 4 | Заявление не дошло в НКО за 30 дней | НКО → `blocked` | **Поддержка/НКО**: повторная подача / `register` |
| 5 | НКО заблокировала юнит (`blocked`) | Продажи закрыты гейтом, деньги прежних заказов остаются на счёте 40821 | Разбор с НКО |
| 6 | У ФЛ протухла/перевыпущена карта, сменился банк СБП | `editable=true` (самообслуживание) | **Продавец сам** перепривязывает карту / меняет СБП |
| 7 | Закрытие окна по заказу упало | `InitiateSellerPayout`: 3 ретрая (10/60/300 с), затем лог; `ReleaseDeliveredOrders` подберёт заказ снова (`seller_payout_status IS NULL`) | Само; при повторах — лог джобы |
| 8 | Самозанятый ФЛ не подтвердил статус (54-ФЗ) | Налоговые риски при C2C | Подтвердить в «Подключение выплат» |
| 9 | Удаление профиля с активным договором | `deleteProfile` чистит профиль, `is_seller=false`, **юнит в НКО не закрывает** | ⚠️ Открытый вопрос — ручное закрытие через поддержку (см. бэклог) |
| 10 | Заказ отменён, деньги остались на счетах (возврат не запускался или упал) | Сверка: «Заказ отменён, деньги покупателю не возвращены»; деньги заморожены у продавца | **Поддержка**: возврат из админки заказа (`POST admin/orders/{order}/refund`) |
| 11 | Оплата пришла на счёт, а заказ её не видит (`payment_status` ≠ completed) | Сверка: «Оплата пришла на счёт, но в заказе не проведена» | **Поддержка**: разобрать заказ; сверка платежей такой заказ уже не подберёт |
| 12 | Остаток счёта не сходится с историей / выписка не грузится | Сверка: `balance_mismatch` дольше 2 ч или `sync_failed`/`sync_stale` | Проверить `MONETA_*` на VM-2 (синхронизация идёт воркерами), затем «Синхронизировать» в карточке или `sellers:sync-accounts --profile=ID` |
| 13 | Посылка не вручена (СДЭК `NOT_DELIVERED`) | `delivery_status=returned`, выплата не разблокируется; сверка: «Посылка не вручена, деньги покупателю не возвращены» | **Поддержка**: решение по заказу и возврат покупателю |

> Сценарий №6 закрыт доработкой: для ФЛ реквизиты выплат самообслуживаемы в любом статусе.
> №9 — в бэклоге, пока не делаем.

## Заявка на изменение юридических данных

Сквозной канал правок вместо переписки с поддержкой (17.09.2026). Раньше
закрытая анкета предлагала написать на `support@muzilla.ru` — канал без следа:
кто что просил, что решили и почему, нигде не фиксировалось.

```
Продавец (анкета read-only) ──POST profile/seller/change-requests {полная анкета}──▶ Платформа
   Платформа: diff против PayoutSetupPrefill (то же «как есть», что заполняет форму)
              → seller_change_requests {payload 🔒, changed_fields 🔒, status=pending}
   Админ ──GET admin/sellers/change-requests──▶ таблица «Поле | Было | Стало»
   Админ ──POST .../{id}/reject {reason}──▶ статус rejected + письмо продавцу + журнал действий
```

| Что | Где |
|---|---|
| Таблица | `seller_change_requests`, обе колонки с данными — `encrypted:array` (паспорт, расчётный счёт) |
| Правило | одна `pending`-заявка на профиль; повторная отбивается 422 |
| Сравнение | `App\Support\Seller\PayoutSetupPrefill` — общий источник «как есть» с `GET payout-setup/status` |
| Валидация | `ChangeRequestSubmitRequest extends SubmitAllRequest` — правила анкеты целиком, включая контрольную сумму счёта по БИК |
| Право админа | `sellers.moderate` (есть у `admin` и `support`) |
| Фронт | `/seller/payout-setup/change-request` (форма), `/admin/sellers/change-requests` (очередь) |

> ⚠️ **Одобрения пока нет.** Кнопка «Одобрить» в админке задизейблена, маршрута
> `approve` не существует, статус `approved` заведён в enum на будущее. Применение
> изменений к `seller_profiles` и рассылка новых скоупов в НКО остаются ручной
> операцией поддержки через `Admin\MonetaSellerController`. Заявка на этом этапе —
> формализованный запрос и журнал решения, а не автоматическая правка.

## Инструменты поддержки

Админ-ручки `Admin\MonetaSellerController` (`/api/admin/sellers/{sellerProfile}/moneta/*`) — весь ручной инструментарий онбординга:

`show` · `check` (CheckProfile в НКО — что осталось) · `register` · `fill-personal` · `fill-director` · `attach-bank` · `attach-passport` · `accept-conditions` · `agreement` (markAgreementSigned) · `activate`.

Через них поддержка исправляет/переоформляет онбординг продавца, когда самообслуживание заблокировано.

Финансы продавцов — `Admin\SellerFinanceController` (право `finance.view`, корректировка — `finance.payouts`):

| Ручка | Что делает |
|---|---|
| `GET /api/admin/finance/sellers` | счета продавцов: остаток, «ожидает срока», резерв, долг, доступно, состояние синхронизации |
| `GET /api/admin/finance/anomalies` | сверка (см. «Сверка денег продавцов») |
| `GET /api/admin/sellers/{sellerProfile}/finance` | счёт продавца + его расхождения + последние заявки на вывод |
| `GET …/finance/ledger?type=&period=&source=` | история счёта с номером операции НКО и атрибутами выписки |
| `POST …/finance/sync` | подтянуть выписку и остаток сейчас |
| `POST …/finance/adjustments` `{amount, reason}` | корректировка долга: «−» добавляет, «+» гасит; в журнал действий |

Консоль: `php artisan sellers:sync-accounts [--profile=ID] [--since=Y-m-d] [--rebuild]` —
догрузить выписку или пересобрать историю из НКО (учёт площадки не трогается).

Налоговые данные для чека — `Admin\SellerController::updateTax`
(`PATCH /api/admin/sellers/{sellerProfile}/tax`, право `sellers.edit`): система
налогообложения и ставка НДС, см. «Шаг 0.5».

## Ключевые файлы

| Область | Файл |
|---|---|
| Регистрация | `app/Http/Controllers/RegistrationController.php`, `app/Http/Requests/SellerRegistrationRequest.php`, `BecomeSellerRequest.php` |
| Профиль/витрина продавца | `app/Http/Controllers/Api/Profile/SellerProfileController.php`, `app/Services/SellerProfileService.php` |
| Подключение выплат | `app/Http/Controllers/Api/Profile/PayoutSetupController.php` |
| Статусы | `app/Enums/PayoutSetupStatus.php`, `app/Enums/MonetaContractStatus.php`, `app/Enums/SellerPayoutMethod.php` |
| НКО MerchantAPI | `app/Services/Payment/MonetaMerchantApiService.php` |
| Вебхуки НКО | `app/Http/Controllers/Api/Webhook/MonetaMerchantWebhookController.php` |
| Привязка карты ФЛ | `app/Services/Payment/PaymentService.php` (`handleSellerCardBindingWebhook`) |
| Окно удержания | `app/Jobs/ReleaseDeliveredOrders.php`, `app/Jobs/InitiateSellerPayout.php`, `app/Services/Payment/PayoutService.php` (развилка по драйверу), `app/Services/Seller/SellerSettlementService.php` |
| Счёт продавца и выписка | `app/Services/Seller/SellerAccountSync.php`, `app/Services/Seller/Statement/{MerchantApiStatementClient,StatementOperation,StatementLedgerWriter}.php`, `app/Jobs/{ReconcileSellerBalances,SyncSellerAccount}.php`, `app/Listeners/SyncSellerAccountsOnMoneyEvent.php` |
| Сверка | `app/Services/Seller/SellerFinanceAnomalies.php`, `app/Jobs/ReportSellerFinanceAnomalies.php` |
| Вывод | `app/Services/Seller/SellerWithdrawalService.php`, `app/Contracts/Payment/SellerWithdrawalTransport.php`, `app/Services/Seller/Withdrawal/UnconfiguredWithdrawalTransport.php` |
| API счёта | `app/Http/Controllers/Api/Profile/SellerBalanceController.php`, `app/Http/Controllers/Admin/SellerFinanceController.php` |
| Джобы онбординга | `app/Jobs/RegisterSellerInMonetaJob.php`, `ActivateMonetaUnitJob.php`, `ReconcileMonetaContractsJob.php` |
| Модель | `app/Models/SellerProfile.php` |
| Поддержка (админ) | `app/Http/Controllers/Admin/MonetaSellerController.php` |
| Заявки на изменение | `app/Models/SellerChangeRequest.php`, `app/Services/Seller/SellerChangeRequestService.php`, `app/Http/Controllers/{Api/Profile,Admin}/SellerChangeRequestController.php` |
| Фронт продавца | `nuxt/pages/seller/index.vue`, `nuxt/pages/seller/payout-setup/index.vue`, `nuxt/pages/seller/payout-setup/change-request.vue`, `nuxt/components/payout/SetupFormFields.vue`, `nuxt/pages/seller/{finances,balance}.vue` |
| Фронт админки | `nuxt/pages/admin/finance/index.vue`, блок «Финансы» в `nuxt/pages/admin/sellers/[id].vue`, `nuxt/composables/useAdminFinance.ts` |
