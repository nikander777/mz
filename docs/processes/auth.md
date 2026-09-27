# Регистрация и авторизация

> Приоритет: **P1**. Актуально на 2026-09-27.

## Назначение

Создание аккаунта и вход: по телефону с SMS-кодом, по email/паролю, через VK ID; разделение и переключение ролей покупатель/продавец; подтверждение телефона. Механизм — Laravel Sanctum (сессии для SPA).

## Endpoints

Группа `auth` (`main/routes/api.php`), контроллеры `AuthController` и `RegistrationController`.

| Метод | Путь | Назначение |
|---|---|---|
| `POST` | `/api/auth/register/buyer` | Регистрация покупателя |
| `POST` | `/api/auth/register/seller` | Регистрация продавца |
| `POST` | `/api/auth/register/email/send-code` · `/verify` | Код на email до регистрации продавца (throttle 5/10 в мин.) |
| `POST` | `/api/auth/login` | Вход по email/паролю |
| `POST` | `/api/auth/login-by-sms` | Вход по SMS-коду |
| `POST` | `/api/auth/phone/send-code` | Отправить код на телефон |
| `POST` | `/api/auth/phone/verify` | Подтвердить телефон |
| `POST` | `/api/auth/become-seller` / `become-buyer` | Переключение роли |
| `GET` | `/api/auth/me` | Текущий пользователь |
| `GET` | `/api/auth/vk/redirect` · `/vk/callback` | Вход через VK ID (`web.php`) |

Middleware защиты: `auth:web`, `EnsurePhoneIsVerifiedApi`. Восстановление пароля (SMS + email-код) — отдельные публичные ручки `auth/password/*`.

## Подтверждённый email и согласия

С 27.09.2026 подтверждённый email (`users.email_verified_at`) обязателен продавцу и для оформления заказа:

- **Регистрация продавца** — в форме шаг «Подтвердите e-mail»: код уходит через `register/email/send-code` (тип `registration`, занятый или синтетический адрес → 422), `register/email/verify` помечает его подтверждённым на 24 ч. `registerSeller` без такого кода отвечает 422 (`errors.email`), с кодом — ставит `email_verified_at` и удаляет код.
- **«Стать продавцом» из ЛК** — `become-seller` без подтверждённой почты → 403 `email_not_verified`; на `/seller/register` плашка с `EmailVerificationModal`.
- **Оформление заказа** — `POST /api/orders/checkout` за middleware `EnsureEmailVerifiedApi` (403 `email_not_verified`); предрасчёт открыт. На `/checkout` вместо способа оплаты — блок подтверждения (`CheckoutEmailVerification`, ручки `/api/auth/email/*`).

Покупатель регистрируется без подтверждения email и без города (`city` nullable). Согласия в формах:

- обязательное (фронт, `required`): покупатель — Условия продажи товаров + Политика ПДн + Согласие на обработку ПДн; продавец — Политика ПДн + Согласие на обработку ПДн (плюс отдельный акцепт оферты);
- необязательное `marketing_consent` (`/subscribe-agreement`) — `User::recordMarketingConsent()` пишет `users.marketing_consent_at/_ip` и включает `marketing_email` в настройках уведомлений.

Тесты: `tests/Feature/RegistrationEmailAndConsentTest.php`.

## Вход под пользователем из админки

`POST /api/admin/users/{id}/impersonate` (`Admin\ImpersonationController`) подменяет текущую сессию сессией пользователя: `Auth::login()` мигрирует идентификатор сессии с `destroy: true`, поэтому админская сессия уничтожается. **Возврата нет** — чтобы снова попасть в админку, администратор входит своим аккаунтом обычным способом.

Гейт (одно правило на всех — `User::canBeImpersonatedBy()`, по нему же считается поле `can_impersonate` в `Admin\UserResource`, по которому админка рисует кнопку):

- право `users.impersonate` (роли `super-admin`, `admin`; выдаётся миграцией `2026_09_19_000100_add_users_impersonate_permission`);
- роль уровня `super-admin`/`admin` — прочим админским ролям (`support`, `moderator`, …) вход закрыт;
- под собой — 422, под сотрудником с доступом в админ-панель (`CheckAdminAccess::ADMIN_ROLES`) — 403: иначе `admin` получил бы сессию `super-admin`'а.

Пометки об имперсонации в сессии и в `/api/auth/me` сознательно нет — на сайте это обычная сессия пользователя. Единственный след — запись `login` в `admin_activity_logs` (пишется **до** подмены сессии, от имени админа). Фронт после успешного ответа делает полную перезагрузку (`window.location`), иначе в памяти SPA остались бы identity, Pinia-сторы и подписки Echo прежнего аккаунта.

## Как тестировать

**Покрытие:** ✅ ~23 (`tests/Feature/Auth/*`). Хорошо закрыто — руками гонять только по изменениям. Пробел: 2FA, linking VK-аккаунта. См. [матрицу](/testing/coverage-matrix).

Вход под пользователем — `tests/Feature/Admin/AdminImpersonationTest.php` (17 тестов: гейт по ролям и праву, запрет под сотрудником и под собой, журнал, флаг `can_impersonate`).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллеры | `app/Http/Controllers/{AuthController,RegistrationController}.php`, `app/Http/Controllers/Admin/ImpersonationController.php` |
| Сервисы | `app/Services/{VerificationService,SmsService,SocialAuthService}.php` |
| Модели | `app/Models/{User,VerificationCode,SellerProfile}.php` |
| Frontend | `nuxt/pages/{register,login,verify-phone}.vue`, `nuxt/components/Auth*`, `nuxt/stores/auth.ts` |
| Интеграции | SMS-провайдер (`config/services.sms`), VK ID (`config/services.vk_id`) |

