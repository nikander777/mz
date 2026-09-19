# Регистрация и авторизация

> Приоритет: **P1**. Актуально на 2026-07-05.

## Назначение

Создание аккаунта и вход: по телефону с SMS-кодом, по email/паролю, через VK ID; разделение и переключение ролей покупатель/продавец; подтверждение телефона. Механизм — Laravel Sanctum (сессии для SPA).

## Endpoints

Группа `auth` (`main/routes/api.php`), контроллеры `AuthController` и `RegistrationController`.

| Метод | Путь | Назначение |
|---|---|---|
| `POST` | `/api/auth/register/buyer` | Регистрация покупателя |
| `POST` | `/api/auth/register/seller` | Регистрация продавца |
| `POST` | `/api/auth/login` | Вход по email/паролю |
| `POST` | `/api/auth/login-by-sms` | Вход по SMS-коду |
| `POST` | `/api/auth/phone/send-code` | Отправить код на телефон |
| `POST` | `/api/auth/phone/verify` | Подтвердить телефон |
| `POST` | `/api/auth/become-seller` / `become-buyer` | Переключение роли |
| `GET` | `/api/auth/me` | Текущий пользователь |
| `GET` | `/api/auth/vk/redirect` · `/vk/callback` | Вход через VK ID (`web.php`) |

Middleware защиты: `auth:web`, `EnsurePhoneIsVerifiedApi`. Восстановление пароля (SMS + email-код) — отдельные публичные ручки `auth/password/*`.

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

