# Настройки .env для продакшена

## Основные настройки приложения
```bash
APP_NAME=MUZILLA
APP_ENV=production
APP_DEBUG=false
APP_KEY=ваш_ключ_здесь
APP_URL=https://mz.nadev.ru
```

## Настройки сессий (КРИТИЧЕСКИ ВАЖНО!)
```bash
SESSION_DRIVER=database
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=mz.nadev.ru
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=lax
```

## Настройки Sanctum (КРИТИЧЕСКИ ВАЖНО!)
```bash
SANCTUM_STATEFUL_DOMAINS=mz.nadev.ru,main.nadev.ru,nuxt.nadev.ru
SANCTUM_GUARD=web
```

## Настройки CORS
```bash
# Эти переменные должны быть установлены для CORS
FRONTEND_URL=https://mz.nadev.ru
NUXT_URL=https://nuxt.nadev.ru
```

## После изменения .env на продакшене выполните:
```bash
php artisan config:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Перезапустите веб-сервер
sudo systemctl reload php8.2-fpm
sudo systemctl reload nginx
```

## Проверьте диагностику:
```bash
curl https://mz.nadev.ru/debug-csrf
```

Должно показать:
- session_domain: "mz.nadev.ru"
- session_secure: true
- sanctum_stateful_domains содержит "mz.nadev.ru"
- has_session_table: true