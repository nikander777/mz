# Флоу продавца: данные, выплаты, договор с НКО

> Каноничный документ по жизненному циклу продавца MUZILLA: кто что заполняет,
> куда летят данные, как устроены выплаты и что делать, если что-то пошло не так.
> Актуально на 2026-08-31.

## Содержание

1. [Действующие лица](#действующие-лица)
2. [Где что хранится](#где-что-хранится)
3. [Обзор жизненного цикла](#обзор-жизненного-цикла)
4. [Этап 1. Регистрация продавца](#этап-1-регистрация-продавца)
5. [Этап 2. Витрина](#этап-2-витрина)
6. [Этап 3a. Подключение выплат — физлицо](#этап-3a-подключение-выплат--физлицо-individual)
7. [Этап 3b. Подключение выплат — ЮЛ/ИП](#этап-3b-подключение-выплат--юл--ип)
8. [Этап 4. Заказ → оплата](#этап-4-заказ--оплата-деньги-на-транзит)
9. [Этап 5. Выплата продавцу](#этап-5-выплата-продавцу)
10. [Статусы и блокировка](#статусы-и-блокировка)
11. [Что делать, если что-то пошло не так](#что-делать-если-что-то-пошло-не-так)
12. [Инструменты поддержки](#инструменты-поддержки)
13. [Ключевые файлы](#ключевые-файлы)

---

## Действующие лица

| Актор | Роль |
|---|---|
| **Продавец** | Заполняет профиль, реквизиты выплат, подписывает оферту |
| **Покупатель** | Оплачивает заказ, подтверждает получение |
| **Платформа** (Laravel `main`) | Хранит данные, оркестрирует онбординг, инициирует выплаты |
| **НКО МОНЕТА** | Платёжный провайдер: транзитный счёт, регистрация ЮЛ/ИП, договор, выплаты |
| **DaData** | Автозаполнение по ИНН из ЕГРЮЛ/ЕГРИП |
| **Поддержка** (админка) | Ручное управление онбордингом через `Admin\MonetaSellerController` |

## Где что хранится

| Таблица | Что лежит |
|---|---|
| `users` | ФИО, `username`, `city`, `email`, `phone`, `is_seller`, `registration_type`, аватар + **витрина**: `description`, `contacts`, `delivery_payment`, `standard_description`, `auto_message` |
| `seller_profiles` | **Идентификация:** `legal_form`, `inn`, `company_name`, `company_legal_form`, `kpp`, `ogrn`, `ogrnip`, `legal_address`, `jurisdiction`, `date_of_birth` · **НКО:** `moneta_unit_id`, `moneta_account_id`, `moneta_contract_status`, `agreement_signed_at`, `agreement_doc_path`, `moneta_synced_at` · **ФЛ-выплаты:** `payout_method`, `payout_card_token` (🔒hidden), `payout_card_mask`, `payout_sbp_phone`, `payout_sbp_bank_id`, `self_employed_confirmed_at` · **Анкета:** `payout_setup_data` (🔒AES-encrypted: паспорт, банк, согласия) |
| `orders` | `moneta_operation_id`, `seller_payout_status`, `seller_payout_amount`, `seller_payout_at`, `seller_payout_id` |

> 🔒 `payout_card_token` и `payout_setup_data` — в `$hidden` модели, наружу через API не отдаются.
> `payout_setup_data` шифруется AES-256 через `APP_KEY` (cast `encrypted:array`).

## Обзор жизненного цикла

```
Регистрация (разово: ФИО, юр.форма, реквизиты компании)
   → Витрина (описание/контакты/доставка) — редактируется всегда
   → Подключение выплат (ЮЛ/ИП: онбординг в НКО + договор)
   → ⛔ ГЕЙТ: пока анкету не одобрила НКО, лоты продавца НЕ ВИДНЫ в каталоге
   → Заказ → оплата → деньги на транзитном счёте платформы
   → Подтверждение получения покупателем → выплата продавцу
```

Заводить лоты продавец может сразу после регистрации — ждать одобрения
с пустым кабинетом не нужно. Невидимы они только для покупателей.

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
| «Ставка НДС» (необязательное: 20/10/0/без НДС/расчётные) | `seller_profiles.default_vat_code` | явное значение перебивает выведенное — у ОСНО бывают льготные ставки |

Резолв ставки на позицию чека:
`order_items.vat_code` ← `products.vat_code` ?? `seller_profiles.default_vat_code`
?? `payments.fiscal.default_vat_code`. Дальше она уходит агрегатору полем
`productVatCode` строки номенклатуры `/api/invoice` — именно по нему ККТ
агрегатора пробивает чек **от имени продавца**.

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
   → Платформа ──createAccount(unitId)──▶ МОНЕТА ◀── accountId
   → seller_profiles.moneta_account_id = accountId
   → статус active  ✅ можно получать выплаты
```

`ReconcileMonetaContractsJob` периодически досинхронизирует статусы, если webhook потерялся.

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

## Этап 4. Заказ → оплата (деньги на транзит)

```
Покупатель оплачивает заказ
   → деньги падают на ТРАНЗИТНЫЙ СЧЁТ платформы в МОНЕТА
   → orders.moneta_operation_id фиксирует операцию
   (деньги «висят» на транзите, пока заказ не завершён и продавец не готов)
```

## Этап 5. Выплата продавцу

**Триггер:** покупатель подтвердил получение → событие `OrderCompleted` → джоба **`InitiateSellerPayout`** (очередь, **3 попытки**, backoff 10/60/300 с).

```
InitiateSellerPayout → PayoutService::initiateSellerPayout(order)
   1. calculateSellerAmount(order)              // минус комиссия платформы
   2. assertCanPayout(profile):
        ЮЛ/ИП → должен быть isMonetaActive (contract=active + moneta_account_id)
        ФЛ    → выбран payout_method + реквизиты (card_token | sbp_phone+bank)
   3. seller_payout_status: pending → processing
   4. dispatchPayout(profile):
        ЮЛ/ИП ──payoutToSeller(operationId, moneta_account_id, amount)──▶ МОНЕТА (счёт→счёт)
        ФЛ CARD ──payoutToCard(operationId, card_token, amount)──▶ МОНЕТА (C2C на карту)
        ФЛ SBP  ──payoutToSbp(operationId, sbp_phone, sbp_bank_id, amount)──▶ МОНЕТА (C2C по СБП)
   5. успех  → status=completed, seller_payout_at, seller_payout_id
      неудача → status=failed (джоба ретраит; после 3 — failed() логирует)
```

Деньги уходят **с транзитного счёта** на счёт/карту продавца. Если продавец не готов — `assertCanPayout` бросает, деньги ждут на транзите, выплату можно переинициировать (разрешено из `null`/`failed`).

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
| 2 | Опечатка обнаружена **после** отправки/активации (`verifying`/`active`) | 403 на запись | **Поддержка** (`MonetaSellerController`): `check` → `fill-*`/`attach-*`; при сильном расхождении — `register` заново |
| 3 | Смена юр.формы (ФЛ↔ИП↔ЮЛ) | Read-only (мы закрыли «тихую» смену) | **Поддержка**: новая регистрация юнита + новое заявление |
| 4 | Заявление не дошло в НКО за 30 дней | НКО → `blocked` | **Поддержка/НКО**: повторная подача / `register` |
| 5 | НКО заблокировала юнит (`blocked`) | `assertCanPayout` бросает, выплаты невозможны | Разбор с НКО; деньги копятся на транзите |
| 6 | У ФЛ протухла/перевыпущена карта, сменился банк СБП | `editable=true` (самообслуживание) | **Продавец сам** перепривязывает карту / меняет СБП |
| 7 | Выплата по заказу упала (`failed`) | 3 ретрая (10/60/300с), затем лог | После починки реквизитов — переинициировать выплату |
| 8 | Самозанятый ФЛ не подтвердил статус (54-ФЗ) | Налоговые риски при C2C | Подтвердить в «Подключение выплат» |
| 9 | Удаление профиля с активным договором | `deleteProfile` чистит профиль, `is_seller=false`, **юнит в НКО не закрывает** | ⚠️ Открытый вопрос — ручное закрытие через поддержку (см. бэклог) |

> Сценарий №6 закрыт доработкой: для ФЛ реквизиты выплат самообслуживаемы в любом статусе.
> №9 и сквозной «безопасный канал смены реквизитов» — в бэклоге, пока не делаем.

## Инструменты поддержки

Админ-ручки `Admin\MonetaSellerController` (`/api/admin/sellers/{sellerProfile}/moneta/*`) — весь ручной инструментарий онбординга:

`show` · `check` (CheckProfile в НКО — что осталось) · `register` · `fill-personal` · `fill-director` · `attach-bank` · `attach-passport` · `accept-conditions` · `agreement` (markAgreementSigned) · `activate`.

Через них поддержка исправляет/переоформляет онбординг продавца, когда самообслуживание заблокировано.

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
| Выплаты | `app/Services/Payment/PayoutService.php`, `app/Jobs/InitiateSellerPayout.php` |
| Джобы онбординга | `app/Jobs/RegisterSellerInMonetaJob.php`, `ActivateMonetaUnitJob.php`, `ReconcileMonetaContractsJob.php` |
| Модель | `app/Models/SellerProfile.php` |
| Поддержка (админ) | `app/Http/Controllers/Admin/MonetaSellerController.php` |
| Фронт продавца | `nuxt/pages/seller/index.vue`, `nuxt/pages/seller/payout-setup.vue`, `nuxt/components/payout/IndividualForm.vue` |
