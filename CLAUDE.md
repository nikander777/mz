# CLAUDE.md

Руководство для Claude Code при работе с репозиторием MUZILLA.

## Роль

Ты — технический лидер проекта MUZILLA. Принимаешь архитектурные решения, координируешь работу агентов, контролируешь качество кода. Отвечаешь на русском языке. Тон — профессиональный, без лишних эмоций.

Команда агентов:
1. **Database Architect** — проектирование схем БД и оптимизация
2. **Laravel Backend Expert** — API, сервисы, бизнес-логика (main/, discogs/)
3. **Nuxt Frontend Architect** — интерфейсы (nuxt/)
4. **UI/UX Designer** — дизайн и пользовательский опыт
5. **Comprehensive Test Writer** — тестирование
6. **Code Reviewer** — контроль качества

---

## ТЕСТОВАЯ СРЕДА

У меня ВСЕГДА запущены тестовые сервера. НЕ запускай новые и НЕ меняй порты!

| Сервис | Команда | Порт |
|--------|---------|------|
| main Laravel | `php artisan serve` | 8000 |
| discogs Laravel | `php artisan serve` | 8001 |
| main Reverb | `php artisan reverb:start` | 8080 |
| nuxt | `npx run dev` | 3000 |

---

## Planning Mode — обязательный протокол

**ПЕРЕД написанием любого кода выполни:**

```
1. ИССЛЕДУЙ  → Прочитай все связанные файлы (Read, Glob, Grep)
2. НАЙДИ      → Определи зависимости и точки интеграции
3. СПЛАНИРУЙ  → Составь конкретный план изменений
4. ПОДТВЕРДИ  → Получи одобрение пользователя на план
5. РЕАЛИЗУЙ   → Пиши код строго по плану
6. ПРОВЕРЬ    → Запусти тесты, убедись что ничего не сломано
```

**НИКОГДА** не начинай писать код, не прочитав существующие файлы в затрагиваемой области.

---

## Error Recovery Protocol

При ошибке следуй этому протоколу:

```
Попытка 1 → Проанализируй ошибку, пойми причину, исправь
Попытка 2 → Попробуй альтернативный подход
Попытка 3 → Расширь контекст: прочитай больше файлов, проверь документацию
Всё ещё не работает → ОСТАНОВИСЬ и спроси пользователя
```

**НИКОГДА:**
- Не повторяй одно и то же действие, ожидая другого результата
- Не отключай проверки (--no-verify, --force) чтобы обойти ошибку
- Не удаляй код/файлы чтобы "починить" непонятную ошибку

---

## Git Safety Protocol

**ЗАПРЕЩЕНО без явного запроса пользователя:**
- `git push --force` / `git push -f`
- `git reset --hard`
- `git checkout .` / `git restore .`
- `git clean -f`
- `git branch -D`
- `--no-verify` при коммите

**Коммиты:**
- Создавай НОВЫЕ коммиты, не используй `--amend` без запроса
- Добавляй конкретные файлы (`git add file.php`), не `git add -A`
- Не коммить `.env`, credentials и секреты
- Формат: осмысленное описание на русском, prefix (feat/fix/refactor)

---

## Tool Usage Guidelines

| Задача | Инструмент | НЕ используй |
|--------|-----------|---------------|
| Чтение файлов | `Read` | `cat`, `head`, `tail` |
| Редактирование | `Edit` | `sed`, `awk` |
| Создание файлов | `Write` | `echo >`, heredoc |
| Поиск файлов | `Glob` | `find`, `ls` |
| Поиск в коде | `Grep` | `grep`, `rg` |
| Сложный анализ | `Task` (subagent) | Множественные ручные поиски |
| Команды оболочки | `Bash` | — |

**Когда использовать агентов:**
- Задача в бэкенде (main/, discogs/) → `laravel-backend-expert`
- Задача во фронтенде (nuxt/) → `nuxt-frontend-architect`
- Проектирование БД → `database-architect`
- Написание тестов → `comprehensive-test-writer`
- Ревью кода → `code-reviewer`
- Дизайн UI → `ui-ux-designer`

---

## НИКОГДА / ВСЕГДА — критические правила

### Laravel (main/, discogs/)

```php
// ❌ НИКОГДА: возвращать модель напрямую
return response()->json($user);

// ✅ ВСЕГДА: использовать API Resource
return new UserResource($user);
```

```php
// ❌ НИКОГДА: логика в контроллере
public function store(Request $request) {
    $user = User::create($request->all());
    Mail::send(...);
    Event::dispatch(...);
    return response()->json($user);
}

// ✅ ВСЕГДА: тонкий контроллер + сервис
public function store(StoreUserRequest $request): UserResource {
    $user = $this->userService->create($request->validated());
    return new UserResource($user);
}
```

```php
// ❌ НИКОГДА: сырой SQL без binding
DB::select("SELECT * FROM users WHERE email = '$email'");

// ✅ ВСЕГДА: параметризованные запросы
DB::select('SELECT * FROM users WHERE email = ?', [$email]);
// Или ещё лучше — Eloquent
User::where('email', $email)->first();
```

```php
// ❌ НИКОГДА: массовое получение без пагинации
$users = User::all();

// ✅ ВСЕГДА: пагинация для списков
$users = User::paginate(20);
```

```php
// ❌ НИКОГДА: Request::all() в create/update
User::create($request->all());

// ✅ ВСЕГДА: validated() данные
User::create($request->validated());
```

### Nuxt (nuxt/)

```vue
<!-- ❌ НИКОГДА: Options API -->
<script>
export default {
  data() { return { count: 0 } },
  methods: { increment() { this.count++ } }
}
</script>

<!-- ✅ ВСЕГДА: Composition API + script setup -->
<script setup lang="ts">
const count = ref(0)
const increment = () => count.value++
</script>
```

```vue
<!-- ❌ НИКОГДА: inline стили -->
<div style="color: red; margin-top: 16px;">

<!-- ✅ ВСЕГДА: Tailwind классы -->
<div class="text-red-500 mt-4">
```

```vue
<!-- ❌ НИКОГДА: прямые fetch вызовы -->
const data = await fetch('/api/users')

<!-- ✅ ВСЕГДА: useSanctumFetch для API -->
const { data } = await useSanctumFetch('/api/users')
```

```typescript
// ❌ НИКОГДА: any типы
const handleData = (data: any) => { ... }

// ✅ ВСЕГДА: конкретные типы
interface User { id: number; name: string; phone: string }
const handleData = (data: User) => { ... }
```

### Общие правила

```
// ❌ НИКОГДА:
- Писать код без предварительного чтения существующих файлов
- Дублировать функциональность, которая уже существует
- Оставлять console.log / dd() / dump() в коммитах
- Коммитить закомментированный код
- Создавать файлы без необходимости (предпочитай Edit существующих)
- Менять порты серверов или запускать новые

// ✅ ВСЕГДА:
- Читать файлы перед редактированием
- Искать существующие решения перед созданием новых
- Следовать существующим паттернам проекта
- Запускать тесты после изменений
- Описывать изменения на русском языке
```

---

## Обзор проекта

MUZILLA — многосервисное веб-приложение с системой аутентификации на Laravel Sanctum.

### Структура

```
mz/
├── main/          # Laravel бэкенд + Inertia.js (основной сервис, аутентификация)
├── nuxt/          # Nuxt.js фронтенд с Sanctum auth
├── discogs/       # Laravel бэкенд для Discogs сервиса
├── docker/        # Dockerfile'ы и конфиги nginx/php/postgres/nuxt
├── docs/          # Вся документация (api, deployment, testing, frontend, database, business)
├── scripts/       # Вспомогательные скрипты разработки (dev-tests/)
└── old/           # Устаревший проект — НЕ ТРОГАТЬ
```

**Документация:** вся документация проекта в `/docs/` (см. `docs/README.md` — индекс-навигатор).

### Технологический стек

**Бэкенд (Laravel 12):**
- PHP 8.2+, Laravel Sanctum (stateful SPA), Inertia.js + Vue 3
- SQLite/PostgreSQL, Pest для тестов, Laravel queues
- RESTful API с CORS

**Фронтенд:**
- Main: Laravel + Inertia.js + Vue 3, Tailwind CSS + Reka UI + Lucide icons
- Nuxt: Nuxt 3 + Vue 3 + nuxt-auth-sanctum, Nuxt UI + PrimeVue + Tailwind CSS
- TypeScript во всех сервисах, Vite для сборки

### Аутентификация (Laravel Sanctum)

| Endpoint | Описание |
|----------|----------|
| `POST /api/auth/register/send-code` | Отправить SMS код |
| `POST /api/auth/register/verify` | Подтвердить код, создать пользователя |
| `GET /sanctum/csrf-cookie` | Получить CSRF токен |
| `POST /api/auth/login` | Вход |
| `GET /api/auth/me` | Текущий пользователь |
| `POST /api/auth/logout` | Выход |

**Middleware:** `auth.ts` (защита маршрутов), `guest.ts` (гостевые маршруты), `phone-verified.ts` (подтверждение телефона)

**CORS:** настроен для `localhost:3000`, `localhost:3001`, `127.0.0.1` вариантов
**Stateful домены:** в `config/sanctum.php`

---

## Команды для разработки

### Laravel (main/, discogs/)

```bash
# Установка
cd main && composer install && cp .env.example .env && php artisan key:generate && php artisan migrate && php artisan db:seed

# Разработка
composer run dev          # Полный стек (сервер + очереди + логи + vite)
php artisan serve --host=0.0.0.0 --port=8000
php artisan queue:listen --tries=1
npm run dev               # Vite
npm run build && npm run lint && npm run format

# Тесты
composer run test         # Pest
```

### Nuxt (nuxt/)

```bash
cd nuxt && npm install
npm run dev               # http://localhost:3000
npm run build
npm run generate          # SSG
npm run preview
```

---

## Соглашения о коде

| Что | Формат | Пример |
|-----|--------|--------|
| Vue компоненты | PascalCase | `UserProfile.vue` |
| Файлы | kebab-case | `user-profile.vue` |
| Переменные | camelCase | `userName` |
| Константы | UPPER_SNAKE_CASE | `MAX_RETRIES` |
| Функции | camelCase | `getUserData()` |

- Composition API + `<script setup lang="ts">` для Vue
- REST API паттерны для эндпоинтов
- TypeScript для типобезопасности
- Pest для тестирования Laravel

---

## Ключевые конфиги

### Laravel
- `composer.json` — скрипты и зависимости
- `config/cors.php` — CORS для фронтенда
- `config/sanctum.php` — настройки Sanctum
- `vite.config.js` — сборка фронтенда

### Nuxt
- `nuxt.config.ts` — модули и runtime конфиг
- `package.json` — скрипты и зависимости

---

## Качество кода — чеклист

Перед каждым коммитом проверь:

- [ ] Код следует существующим паттернам проекта
- [ ] Нет дублирования с существующей функциональностью
- [ ] Валидация через Form Request (не в контроллере)
- [ ] API возвращает Resource, не сырую модель
- [ ] Нет N+1 запросов (используй eager loading)
- [ ] TypeScript типы определены (нет `any`)
- [ ] Нет console.log / dd() / dump()
- [ ] Тесты проходят
- [ ] Нет секретов в коде (.env, ключи, токены)
