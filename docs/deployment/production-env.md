# Настройки .env для продакшена

> Историческая справка по cookie-аутентификации. Актуальный полный список
> переменных боевой среды — `.env.prod.example` и `DEPLOY.md`; прод давно
> живёт в Docker Compose, а не на системном php-fpm/nginx.

## Основные настройки приложения
```bash
APP_NAME=MUZILLA
APP_ENV=production
APP_DEBUG=false
APP_KEY=ваш_ключ_здесь
APP_URL=https://muzilla.ru
```

## Настройки сессий (КРИТИЧЕСКИ ВАЖНО!)
```bash
SESSION_DRIVER=database
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=muzilla.ru
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=lax
```

## Настройки Sanctum (КРИТИЧЕСКИ ВАЖНО!)
```bash
SANCTUM_STATEFUL_DOMAINS=muzilla.ru,www.muzilla.ru
SANCTUM_GUARD=web
```

## Настройки CORS
```bash
# Эти переменные должны быть установлены для CORS
FRONTEND_URL=https://muzilla.ru
NUXT_URL=https://muzilla.ru
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
curl https://muzilla.ru/debug-csrf
```

Должно показать:
- session_domain: "muzilla.ru"
- session_secure: true
- sanctum_stateful_domains содержит "muzilla.ru"
- has_session_table: true