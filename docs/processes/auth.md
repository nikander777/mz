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

## Как тестировать

**Покрытие:** ✅ ~23 (`tests/Feature/Auth/*`). Хорошо закрыто — руками гонять только по изменениям. Пробел: 2FA, linking VK-аккаунта. См. [матрицу](/testing/coverage-matrix).

## Ключевые файлы

| Область | Файл |
|---|---|
| Контроллеры | `app/Http/Controllers/{AuthController,RegistrationController}.php` |
| Сервисы | `app/Services/{VerificationService,SmsService,SocialAuthService}.php` |
| Модели | `app/Models/{User,VerificationCode,SellerProfile}.php` |
| Frontend | `nuxt/pages/{register,login,verify-phone}.vue`, `nuxt/components/Auth*`, `nuxt/stores/auth.ts` |
| Интеграции | SMS-провайдер (`config/services.sms`), VK ID (`config/services.vk_id`) |

