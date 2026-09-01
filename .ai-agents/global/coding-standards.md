# Стандарты кода MUZILLA

## PHP/Laravel (main/ и discogs/)
- **Версии**: PHP 8.2+, Laravel 12
- **Стиль**: PSR-12, используем Laravel Pint
- **Типизация**: `declare(strict_types=1)` в новых файлах
- **Именование**: snake_case для БД, camelCase для методов
- **Структура**: app/ стандартная Laravel структура
- **Тестирование**: Pest фреймворк, TDD подход

## JavaScript/TypeScript (nuxt/)
- **Версии**: Node.js 18+, Nuxt 3, Vue 3
- **Стиль**: 2 пробела, одинарные кавычки
- **API**: Composition API для Vue компонентов
- **Именование**: camelCase для переменных, PascalCase для компонентов
- **Структура**: Nuxt 3 структура директорий
- **UI**: PrimeVue + Tailwind CSS

## База данных
- **Разработка**: SQLite (database/database.sqlite)
- **Продакшн**: PostgreSQL
- **Миграции**: Laravel миграции с rollback поддержкой
- **Именование**: snake_case, множественное число для таблиц

## API
- **Стиль**: RESTful с префиксом /api/
- **Версионирование**: Через заголовки при необходимости
- **Ответы**: JSON с единообразной структурой
- **Ошибки**: HTTP коды + детальные сообщения
- **CORS**: Настроен для localhost:3000

## Компоненты Vue
- **Файлы**: kebab-case.vue
- **Именование**: PascalCase для экспорта
- **Структура**: template → script → style
- **Props**: TypeScript интерфейсы
- **События**: camelCase именование

## Обязательные проверки
- [ ] Laravel Pint для форматирования PHP
- [ ] ESLint для JavaScript/TypeScript
- [ ] Pest тесты проходят
- [ ] TypeScript компиляция без ошибок
- [ ] Нет console.log в production коде