# Интеграция управления пользователями в админ-панели

## Обзор

Реализована полная интеграция управления пользователями с реальным API в админ-панели Nuxt. Все страницы переписаны с использованием PrimeVue 4 компонентов вместо Nuxt UI.

## Структура файлов

### Composables

**`/composables/useAdminUsers.ts`**
- Основной composable для работы с API пользователей
- Экспортирует TypeScript типы: `User`, `Role`, `Permission`, `UsersListParams`, `PaginatedUsers`
- Методы:
  - `fetchUsers(params)` - получить список с фильтрами и пагинацией
  - `fetchUser(id)` - получить данные пользователя
  - `createUser(data)` - создать пользователя
  - `updateUser(id, data)` - обновить данные
  - `deleteUser(id)` - удалить пользователя
  - `assignRole(userId, roleId)` - назначить роль
  - `blockUser(userId, blocked, reason)` - блокировать/разблокировать
  - `fetchRoles()` - получить список ролей
  - `fetchPermissions()` - получить список прав доступа
  - `assignPermissions(userId, permissionIds)` - назначить права

### Страницы

**`/pages/admin/users/index.vue`** - Список пользователей
- PrimeVue DataTable с серверной пагинацией
- Фильтры по роли и статусу
- Поиск по имени, email, телефону
- Сортировка по всем колонкам
- Действия: просмотр, редактирование, удаление
- ConfirmDialog для подтверждения удаления

**`/pages/admin/users/[id].vue`** - Просмотр пользователя
- Отображение всех данных пользователя
- Статистика: количество заказов, сумма покупок
- Действия: редактировать, блокировать, удалить
- Быстрые действия: отправка email/SMS, сброс пароля

**`/pages/admin/users/[id]/edit.vue`** - Редактирование пользователя
- Загрузка данных из API
- Использует компонент `AdminUserForm`
- Загрузка ролей и прав доступа
- Редирект после успешного сохранения

**`/pages/admin/users/create.vue`** - Создание пользователя
- Использует компонент `AdminUserForm`
- Загрузка ролей и прав доступа
- Редирект на страницу просмотра после создания

### Компоненты

**`/components/admin/UserForm.vue`** - Форма пользователя
- Единый компонент для создания и редактирования
- PrimeVue компоненты:
  - `InputText` - имя, email
  - `InputMask` - телефон с маской
  - `Password` - пароль с toggle
  - `Dropdown` - выбор роли
  - `Button` - переключение статуса
  - `Accordion` + `Checkbox` - права доступа по категориям
- Полная валидация:
  - Имя (минимум 2 символа)
  - Email (корректный формат)
  - Телефон (опционально, 10-15 цифр)
  - Пароль (минимум 8 символов, подтверждение)
- Группировка прав доступа по категориям

## API эндпоинты

Все запросы идут через `/api/admin/*`:

```
GET    /api/admin/users              - Список пользователей
POST   /api/admin/users              - Создание
GET    /api/admin/users/{id}         - Просмотр
PUT    /api/admin/users/{id}         - Обновление
DELETE /api/admin/users/{id}         - Удаление
POST   /api/admin/users/{id}/assign-role      - Назначить роль
POST   /api/admin/users/{id}/block            - Блокировать
GET    /api/admin/roles              - Список ролей
GET    /api/admin/permissions        - Список прав
```

## Параметры запросов

### Список пользователей (GET /api/admin/users)

Query параметры:
- `page` - номер страницы (default: 1)
- `per_page` - записей на странице (default: 15)
- `search` - поиск по имени, email, телефону
- `role` - фильтр по роли
- `status` - фильтр по статусу
- `sort_by` - поле сортировки
- `sort_order` - направление (asc/desc)

### Создание пользователя (POST /api/admin/users)

Body:
```json
{
  "name": "string",
  "email": "string",
  "phone": "string (optional)",
  "password": "string",
  "password_confirmation": "string",
  "role": "string (optional)",
  "status": "active|inactive|blocked (optional)",
  "permissions": ["string"] (optional)
}
```

### Обновление пользователя (PUT /api/admin/users/{id})

Body (все поля опциональны):
```json
{
  "name": "string",
  "email": "string",
  "phone": "string",
  "password": "string (только если меняем)",
  "password_confirmation": "string",
  "role": "string",
  "status": "active|inactive|blocked",
  "permissions": ["string"]
}
```

### Блокировка (POST /api/admin/users/{id}/block)

Body:
```json
{
  "blocked": true|false,
  "reason": "string (optional)"
}
```

## Используемые PrimeVue компоненты

### Основные
- `Toast` - уведомления
- `ConfirmDialog` - подтверждение действий
- `Button` - кнопки
- `Card` - карточки
- `Skeleton` - загрузка

### Форма
- `InputText` - текстовые поля
- `InputMask` - маскированный ввод
- `Password` - поле пароля
- `Dropdown` - выпадающий список
- `Checkbox` - чекбоксы
- `Accordion` - аккордеон для группировки

### Таблица
- `DataTable` - таблица данных
- `Column` - колонки
- `IconField` + `InputIcon` - поле поиска с иконкой
- `Avatar` - аватар пользователя
- `Tag` - теги для статусов и ролей
- `Chip` - чипы для прав доступа

## Обработка ошибок

Все ошибки API обрабатываются в `useAdminApi.ts`:
- Отображение через PrimeVue Toast
- Поддержка ошибок валидации Laravel
- Автоматический вывод всех ошибок полей

## Loading состояния

Реализованы loading states для:
- Загрузки списка пользователей
- Загрузки данных пользователя
- Сохранения формы
- Удаления пользователя
- Блокировки пользователя

## Валидация

### Клиентская валидация (AdminUserForm)
- Имя: минимум 2 символа
- Email: валидный формат
- Телефон: 10-15 цифр (опционально)
- Пароль: минимум 8 символов (обязателен при создании)
- Подтверждение пароля: совпадение с паролем

### Серверная валидация
Обрабатывается автоматически через `useAdminApi.ts`
Ошибки отображаются через Toast

## Типобезопасность

Все типы экспортируются из `useAdminUsers.ts`:
- `User` - модель пользователя
- `Role` - модель роли
- `Permission` - модель права доступа
- `UsersListParams` - параметры списка
- `PaginatedUsers` - пагинированный результат
- `CreateUserData` - данные для создания
- `UpdateUserData` - данные для обновления
- `BlockUserData` - данные для блокировки

## Конфигурация

Все необходимые PrimeVue компоненты добавлены в `nuxt.config.ts`:
```typescript
components: {
  include: [
    'Avatar', 'Password', 'IconField', 'InputIcon',
    // ... другие компоненты
  ]
}
```

## Масштабируемость

Архитектура позволяет легко:
- Добавлять новые фильтры
- Расширять функционал форм
- Добавлять новые действия с пользователями
- Интегрировать с другими модулями админки

## Производительность

- Серверная пагинация (не загружаем все данные)
- Lazy loading для DataTable
- Skeleton компоненты для улучшения UX
- Оптимизированные запросы (Promise.all для параллельной загрузки)

## Безопасность

- Все запросы через авторизованный API
- CSRF защита через Sanctum
- Middleware для проверки прав доступа
- Валидация на клиенте и сервере
