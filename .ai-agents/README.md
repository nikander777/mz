# AI-Агенты для MUZILLA

Система организации работы с AI-ассистентами для проекта MUZILLA.

## Структура

```
.ai-agents/
├── global/                  # Общие правила и контекст
│   ├── project-context.md   # Контекст проекта MUZILLA
│   └── coding-standards.md  # Стандарты кода
├── specialists/             # Специализированные агенты
│   ├── product-management.prompt.md    # Управление продуктами
│   ├── discogs-integration.prompt.md   # Интеграция Discogs API
│   └── authentication.prompt.md        # Система аутентификации
├── workflows/              # Рабочие процессы
│   └── fix-product-create-page.md      # Исправление создания товара
├── setup-muzilla.sh        # Скрипт настройки среды
└── README.md               # Эта документация
```

## Быстрый старт

### 1. Настройка среды разработки

```bash
# Запустить скрипт настройки
./.ai-agents/setup-muzilla.sh

# Или установить git hooks вручную
git config core.hooksPath .hooks
chmod +x .hooks/*
```

### 2. Использование алиасов

После настройки доступны команды:

```bash
# Запуск сервисов (НЕ НУЖНО - уже запущены!)
mz-main      # Laravel main на :8000
mz-discogs   # Laravel discogs на :8001
mz-nuxt      # Nuxt frontend на :3000

# Тестирование
mz-test-main    # Тесты Laravel main
mz-test-nuxt    # Тесты Nuxt
mz-check        # Все проверки
mz-fix          # Исправления кода
```

### 3. Работа с AI-агентами

При работе с Claude Code используйте промпты:

```markdown
Используй специалиста по продуктам MUZILLA из .ai-agents/specialists/product-management.prompt.md для работы с товарами.

Следуй контексту проекта из .ai-agents/global/project-context.md.
```

## Специализированные агенты

### Product Management Agent
**Файл**: `specialists/product-management.prompt.md`

Используйте для:
- Создания и редактирования товаров
- Работы с категориями
- Интеграции с Discogs
- Системы аукционов
- Загрузки медиа

### Discogs Integration Agent
**Файл**: `specialists/discogs-integration.prompt.md`

Используйте для:
- Поиска релизов в Discogs API
- Настройки API proxy
- Обработки ошибок интеграции
- Кэширования результатов

### Authentication Agent
**Файл**: `specialists/authentication.prompt.md`

Используйте для:
- Настройки Laravel Sanctum
- Системы SMS регистрации
- Middleware и защиты роутов
- CSRF и безопасности

## Рабочие процессы

### Разработка новой функции

1. **Планирование**: Проанализировать требования
2. **Архитектура**: Спроектировать решение
3. **Тестирование**: Написать falling тесты (TDD)
4. **Реализация**: Код для прохождения тестов
5. **Интеграция**: Проверка совместимости
6. **Документация**: Обновление документации

### Исправление багов

1. **Воспроизведение**: Создать тест для бага
2. **Анализ**: Найти первопричину
3. **Исправление**: Минимальные изменения
4. **Тестирование**: Убедиться что баг исправлен
5. **Регрессия**: Проверить что ничего не сломалось

## Git Hooks

### Pre-commit Hook
Автоматически проверяет:
- Синтаксис PHP и JS/TS
- Laravel Pint (форматирование PHP)
- ESLint (JS/TS/Vue)
- TypeScript компиляция
- Отладочный код (dd, console.log)
- .env файлы

### Как обойти hooks (только в крайнем случае)
```bash
git commit --no-verify -m "Сообщение"
```

## Стандарты качества

### Laravel (main/ и discogs/)
- ✅ PHP 8.2+, Laravel 12
- ✅ PSR-12 форматирование (Laravel Pint)
- ✅ Pest тестирование
- ✅ SQLite для разработки
- ✅ Sanctum аутентификация

### Nuxt (nuxt/)
- ✅ Nuxt 3, Vue 3, TypeScript
- ✅ PrimeVue + Tailwind CSS
- ✅ Composition API
- ✅ ESLint + форматирование
- ✅ Vitest тестирование

## Команды проверки

```bash
# Laravel main
cd main
composer lint     # Проверка стиля
composer test     # Запуск тестов
composer check    # Все проверки

# Nuxt
cd nuxt
npm run lint      # ESLint
npm run typecheck # TypeScript
npm run test      # Vitest
npm run check     # Все проверки
```

## Часто используемые паттерны

### API запросы в Nuxt
```typescript
// Используй useSanctumFetch для API
const data = await useSanctumFetch('/api/products', {
  method: 'POST',
  body: formData
})
```

### Валидация в Laravel
```php
// Всегда используй Request классы
class StoreProductRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'title' => 'required|string|max:255',
            'price' => 'required|numeric|min:0',
        ];
    }
}
```

### Компоненты Vue
```vue
<script setup lang="ts">
// Используй Composition API + TypeScript
interface Props {
  product: Product
}

const props = defineProps<Props>()
const emit = defineEmits<{
  save: [product: Product]
}>()
</script>
```

## Безопасность

### НИКОГДА не коммитить:
- `.env` файлы
- Пароли и токены
- Отладочный код (`dd`, `console.log`)
- Закомментированный код

### ВСЕГДА проверять:
- CSRF токены в формах
- Валидацию на backend И frontend
- Права доступа к ресурсам
- Санитизацию пользовательских данных

## Поддержка

При проблемах:
1. Проверьте логи: `main/storage/logs/laravel.log`
2. Запустите проверки: `mz-check`
3. Проверьте git hooks: `.hooks/pre-commit`
4. Обратитесь к специализированным агентам в `specialists/`

---

**Важно**: Сервисы уже запущены на стандартных портах. Не перезапускайте их без необходимости!