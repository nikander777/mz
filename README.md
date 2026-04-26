# Авторизация через sidebase/nuxt-auth с Laravel Sanctum

Этот проект демонстрирует реализацию авторизации между Nuxt.js фронтендом и Laravel бэкендом с использованием Laravel Sanctum.

## Структура проекта

```
mz/
├── main/          # Laravel бэкенд (основной сервис)
├── nuxt/          # Nuxt.js фронтенд
├── discogs/       # Laravel бэкенд для сервиса дискографии
├── docker/        # Dockerfile'ы и конфиги nginx/php/postgres/nuxt
├── docs/          # Документация (api, deployment, testing, frontend, database, business)
├── scripts/       # Вспомогательные скрипты разработки (dev-tests/)
└── old/           # Устаревший Yii проект — не трогать
```

📚 **Документация:** вся документация централизована в [`docs/`](docs/README.md) — API, deployment, testing, architecture.

## Настройка Laravel бэкенда

### 1. Установка зависимостей

```bash
cd main
composer install
```

### 2. Настройка базы данных

Создайте файл `.env` на основе `.env.example` и настройте подключение к базе данных:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=your_database
DB_USERNAME=your_username
DB_PASSWORD=your_password
```

### 3. Миграции и сиды

```bash
php artisan migrate
php artisan db:seed
```

### 4. Настройка CORS

Файл `config/cors.php` уже настроен для работы с Nuxt.js:

```php
'allowed_origins' => [
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:3001',
    'http://127.0.0.1:3001',
],
'supports_credentials' => true,
```

### 5. Настройка Sanctum

Файл `config/sanctum.php` настроен для работы с SPA:

```php
'stateful' => explode(',', env('SANCTUM_STATEFUL_DOMAINS', sprintf(
    '%s%s',
    'localhost,localhost:3000,localhost:3001,127.0.0.1,127.0.0.1:8000,127.0.0.1:3000,127.0.0.1:3001,::1',
    Sanctum::currentApplicationUrlWithPort(),
))),
```

### 6. Запуск Laravel сервера

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

## Настройка Nuxt.js фронтенда

### 1. Установка зависимостей

```bash
cd nuxt
npm install
```

### 2. Настройка переменных окружения

Создайте файл `.env` в папке `nuxt`:

```env
BACKEND_BASE_URL=http://localhost:8000
```

### 3. Конфигурация Nuxt

Файл `nuxt.config.ts` уже настроен:

```typescript
export default defineNuxtConfig({
  runtimeConfig: {
    apiBaseUrl: process.env.DISCOGS_BASE_URL || 'http://localhost:8000',
    apiToken: process.env.DISCOGS_API_TOKEN || 'mbrainz-FSzz-3333',
  },

  sanctum: {
    baseUrl: process.env.BACKEND_BASE_URL || 'http://localhost:8000',
  },

  modules: [
    'nuxt-headlessui',
    '@nuxt/ui',
    '@nuxt/test-utils',
    '@nuxt/image',
    '@nuxt/icon',
    '@nuxt/content',
    '@nuxt/eslint',
    '@nuxt/fonts',
    '@nuxt/scripts',
    '@vueuse/nuxt',
    'nuxt-auth-sanctum'
  ]
})
```

### 4. Запуск Nuxt сервера

```bash
npm run dev
```

## Функциональность

### Реализованные возможности:

1. **Регистрация пользователей** с подтверждением по SMS
2. **Вход в систему** по email и паролю
3. **Защищенные маршруты** с middleware
4. **Управление сессиями** через Laravel Sanctum
5. **Автоматическая инициализация** авторизации при загрузке приложения

### API Endpoints (Laravel):

- `POST /api/auth/register/send-code` - Отправка кода для регистрации
- `POST /api/auth/register/verify` - Подтверждение регистрации
- `POST /api/auth/login` - Вход в систему
- `GET /api/auth/me` - Получение информации о пользователе
- `POST /api/auth/logout` - Выход из системы
- `GET /sanctum/csrf-cookie` - Получение CSRF токена

### Nuxt API Routes:

- `/api/auth/login` - Прокси для входа
- `/api/auth/me` - Прокси для получения пользователя
- `/api/auth/logout` - Прокси для выхода
- `/api/auth/csrf` - Прокси для CSRF токена

## Компоненты

### AuthLoginForm.vue
Форма входа с валидацией и обработкой ошибок.

### AuthRegisterForm.vue
Форма регистрации с валидацией всех полей.

### AuthVerifyForm.vue
Форма подтверждения регистрации по SMS коду.

### AppHeader.vue
Заголовок с навигацией и кнопкой выхода.

## Middleware

### auth.ts
Защищает маршруты, требующие авторизации. Перенаправляет на `/login` если пользователь не авторизован.

### guest.ts
Защищает гостевые маршруты. Перенаправляет на `/` если пользователь уже авторизован.

## Composable

### useAuth.ts
Основной composable для работы с авторизацией:

```typescript
const { 
  user, 
  isAuthenticated, 
  isLoading, 
  error,
  login,
  register,
  verifyRegistration,
  fetchUser,
  logout,
  init 
} = useAuth()
```

## Страницы

- `/` - Главная страница с приветствием
- `/login` - Страница входа
- `/register` - Страница регистрации
- `/profile` - Защищенная страница профиля

## Безопасность

1. **CSRF защита** - автоматическое получение CSRF токенов
2. **Валидация данных** - на фронтенде и бэкенде
3. **Безопасные токены** - Laravel Sanctum
4. **CORS настройки** - только разрешенные домены
5. **Хеширование паролей** - bcrypt

## Тестирование

1. Запустите Laravel сервер: `php artisan serve`
2. Запустите Nuxt сервер: `npm run dev`
3. Откройте http://localhost:3000
4. Попробуйте зарегистрироваться и войти в систему

## Дополнительные возможности

Для полной функциональности можно добавить:

1. **Восстановление пароля** по SMS
2. **Верификация email** 
3. **Двухфакторная аутентификация**
4. **Социальная авторизация** (Google, Facebook)
5. **Управление профилем** пользователя
6. **История сессий** и их управление

