# Тестирование авторизации

## Быстрый старт

### 1. Запуск Laravel бэкенда
```bash
cd main
php artisan serve --host=0.0.0.0 --port=8000
```

### 2. Запуск Nuxt фронтенда
```bash
cd nuxt
npm run dev
```

### 3. Открыть в браузере
- Frontend: http://localhost:3000
- Backend API: http://localhost:8000

## Тестирование функциональности

### Регистрация нового пользователя
1. Перейдите на http://localhost:3000/register
2. Заполните форму регистрации:
   - Имя: `Тест Пользователь`
   - Email: `test@example.com`
   - Телефон: `+79991234567`
   - Пароль: `password123`
   - Подтверждение пароля: `password123`
3. Нажмите "Зарегистрироваться"
4. Введите код подтверждения (6 цифр)
5. После успешной регистрации вы будете перенаправлены на главную страницу

### Вход в систему
1. Перейдите на http://localhost:3000/login
2. Введите email и пароль зарегистрированного пользователя
3. Нажмите "Войти"
4. После успешного входа вы увидите приветствие на главной странице

### Проверка защищенных маршрутов
1. Войдите в систему
2. Перейдите на http://localhost:3000/profile
3. Вы должны увидеть страницу профиля с информацией о пользователе
4. Попробуйте выйти из системы и снова перейти на /profile - вас перенаправит на страницу входа

### Проверка гостевых маршрутов
1. Выйдите из системы
2. Перейдите на http://localhost:3000/login или /register
3. Войдите в систему
4. Попробуйте снова перейти на /login или /register - вас перенаправит на главную страницу

## Проверка API endpoints

### Тестирование через Postman/curl

#### 1. Регистрация
```bash
curl -X POST http://localhost:8000/api/auth/register/send-code \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Тест Пользователь",
    "email": "test@example.com",
    "phone": "+79991234567",
    "password": "password123",
    "password_confirmation": "password123"
  }'
```

#### 2. Подтверждение регистрации
```bash
curl -X POST http://localhost:8000/api/auth/register/verify \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+79991234567",
    "code": "123456"
  }'
```

#### 3. Вход в систему
```bash
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

#### 4. Получение информации о пользователе
```bash
curl -X GET http://localhost:8000/api/auth/me \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

#### 5. Выход из системы
```bash
curl -X POST http://localhost:8000/api/auth/logout \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

## Проверка безопасности

### CSRF защита
- Все POST запросы автоматически получают CSRF токен
- Проверьте в Network tab браузера, что запросы содержат CSRF заголовки

### CORS настройки
- Проверьте, что запросы с localhost:3000 принимаются бэкендом
- Проверьте, что credentials передаются корректно

### Валидация данных
- Попробуйте отправить некорректные данные в формах
- Проверьте, что ошибки валидации отображаются корректно

## Отладка

### Проверка консоли браузера
- Откройте Developer Tools (F12)
- Проверьте вкладку Console на наличие ошибок
- Проверьте вкладку Network для анализа запросов

### Проверка логов Laravel
```bash
cd main
tail -f storage/logs/laravel.log
```

### Проверка состояния авторизации
В консоли браузера выполните:
```javascript
// Проверка токена
console.log(localStorage.getItem('auth_token'))

// Проверка состояния авторизации
console.log(useAuth().isAuthenticated.value)
console.log(useAuth().user.value)
```

## Возможные проблемы

### 1. CORS ошибки
- Убедитесь, что Laravel сервер запущен на порту 8000
- Проверьте настройки CORS в `main/config/cors.php`

### 2. CSRF ошибки
- Убедитесь, что запросы идут через Nuxt API routes
- Проверьте, что CSRF токен получается перед POST запросами

### 3. Ошибки авторизации
- Проверьте, что токен сохраняется в localStorage
- Проверьте, что заголовок Authorization передается корректно

### 4. Проблемы с базой данных
- Убедитесь, что миграции выполнены: `php artisan migrate`
- Проверьте подключение к базе данных в `.env`



