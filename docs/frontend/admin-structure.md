# Структура админ-панели MUZILLA

## Обзор

Полноценная административная панель для управления всеми аспектами платформы MUZILLA. Построена на Nuxt 3, Vue 3 Composition API, Nuxt UI и PrimeVue 4.

## Технологии

- **Frontend Framework**: Nuxt 3
- **UI Framework**: Vue 3 (Composition API)
- **UI Libraries**: Nuxt UI + PrimeVue 4
- **Styling**: Tailwind CSS
- **State Management**: Composables
- **Authentication**: nuxt-auth-sanctum
- **Permissions**: usePermissions composable

## Структура проекта

### Layouts
- `/layouts/admin.vue` - Основной layout с sidebar навигацией, breadcrumbs, поиском

### Страницы (Pages)

#### Dashboard
- `/pages/admin/index.vue` - Главная страница с аналитикой, графиками и статистикой

#### Пользователи (Users)
- `/pages/admin/users/index.vue` - Список пользователей с фильтрами
- `/pages/admin/users/[id].vue` - Просмотр пользователя
- `/pages/admin/users/[id]/edit.vue` - Редактирование пользователя
- `/pages/admin/users/create.vue` - Создание пользователя

**Функционал:**
- Таблица с пагинацией, поиском и сортировкой
- Фильтры по роли и статусу
- Блокировка/разблокировка пользователей
- Назначение ролей и прав доступа
- Просмотр статистики пользователя (заказы, сумма покупок)

#### Товары (Products)
- `/pages/admin/products/index.vue` - Каталог товаров
- `/pages/admin/products/[id].vue` - Просмотр товара
- `/pages/admin/products/[id]/edit.vue` - Редактирование товара
- `/pages/admin/products/create.vue` - Создание товара

**Функционал:**
- Управление товарами (CRUD)
- Загрузка изображений (множественная)
- Управление ценами, скидками
- Статусы: черновик, опубликован, архивирован
- Управление остатками
- Категории и бренды

#### Заказы (Orders)
- `/pages/admin/orders/index.vue` - Список заказов
- `/pages/admin/orders/[id].vue` - Детали заказа

**Функционал:**
- Просмотр и фильтрация заказов
- Изменение статуса заказа
- Информация о клиенте и доставке
- История изменений

#### Отзывы (Reviews)
- `/pages/admin/reviews/index.vue` - Модерация отзывов

**Функционал:**
- Табы по статусам (на модерации, одобренные, отклоненные)
- Одобрение/отклонение отзывов
- Просмотр пользователя и товара
- Удаление отзывов

#### Категории (Categories)
- `/pages/admin/categories/index.vue` - Управление категориями

**Функционал:**
- Древовидная структура категорий
- Drag-and-drop для изменения порядка
- CRUD операции с категориями
- Подсчет товаров в категории

#### Сообщения (Messages)
- `/pages/admin/messages/index.vue` - Сообщения пользователей

**Функционал:**
- Статусы: новые, в работе, решенные
- Ответ на сообщения
- Изменение статуса

#### Настройки (Settings)
- `/pages/admin/settings/index.vue` - Настройки системы

**Функционал:**
- Табы: Общие, Email, Оплата, Доставка, Уведомления
- Конфигурация SMTP
- Настройка способов оплаты
- Настройка доставки

#### Роли и права (Roles)
- `/pages/admin/roles/index.vue` - Управление ролями

**Функционал:**
- Список ролей с статистикой
- Создание/редактирование ролей
- Управление правами доступа через PermissionsMatrix

### Компоненты (Components)

#### Формы
- `AdminUserForm.vue` - Форма пользователя
  - Валидация полей
  - Загрузка аватара
  - Выбор роли и статуса
  - Назначение прав

- `AdminProductForm.vue` - Форма товара
  - Множественная загрузка изображений
  - Управление ценами и скидками
  - Управление остатками
  - Статусы публикации

- `AdminImageUpload.vue` - Загрузка изображений
  - Поддержка множественной загрузки
  - Preview изображений
  - Drag-and-drop
  - Валидация размера

#### UI компоненты
- `AdminDataTable.vue` - Таблица данных
  - Пагинация
  - Сортировка
  - Поиск
  - Фильтры

- `AdminStatCard.vue` - Статистическая карточка
  - Отображение метрик
  - Тренды (рост/падение)
  - Иконки

- `AdminChartCard.vue` - Карточка с графиком
  - Интеграция Chart.js
  - Выбор периода
  - Различные типы графиков

- `AdminOrderStatusBadge.vue` - Badge статуса заказа
  - Цветовая индикация
  - Иконки статусов

- `AdminCategoryTree.vue` - Древовидный список категорий
  - Рекурсивный компонент
  - Раскрытие/сворачивание
  - CRUD операции

- `AdminReviewCard.vue` - Карточка отзыва
  - Информация о пользователе и товаре
  - Рейтинг
  - Действия модерации

- `AdminPermissionsMatrix.vue` - Матрица прав
  - Группировка по категориям
  - Массовое включение/выключение
  - Индикация выбранных прав

- `AdminCard.vue` - Универсальная карточка
- `AdminBadge.vue` - Badge компонент
- `AdminStatusBadge.vue` - Badge для статусов
- `AdminEmptyState.vue` - Пустое состояние
- `AdminQuickActions.vue` - Быстрые действия
- `AdminTopItems.vue` - Топ элементы

### Composables

#### useAdminApi
```typescript
const adminApi = useAdminApi()

// GET запрос
await adminApi.get('/users')

// POST запрос
await adminApi.post('/users', userData)

// PUT запрос
await adminApi.put('/users/1', userData)

// DELETE запрос
await adminApi.delete('/users/1')
```

**Функции:**
- Автоматическая авторизация (Bearer token)
- Обработка ошибок с toast уведомлениями
- Типизация TypeScript

#### useAdminStats
```typescript
const {
  stats,
  salesChart,
  recentOrders,
  activities,
  isLoading,
  loadDashboard
} = useAdminStats()
```

**Функции:**
- Загрузка статистики dashboard
- Данные для графиков
- Последние заказы и активность

#### usePermissions
```typescript
const {
  hasPermission,
  hasAnyPermission,
  hasRole,
  isSuperAdmin,
  canAccessAdmin
} = usePermissions()

// Проверка прав
if (hasPermission('edit_users')) {
  // Показать кнопку редактирования
}
```

**Функции:**
- Проверка прав доступа
- Проверка ролей
- Проверка доступа к админ-панели

## Система прав доступа

### Роли
- `super-admin` - Полный доступ
- `admin` - Администратор
- `manager` - Менеджер
- `moderator` - Модератор
- `user` - Пользователь

### Права доступа
```typescript
// Пользователи
'view_users', 'create_users', 'edit_users', 'delete_users', 'block_users'

// Товары
'view_products', 'create_products', 'edit_products', 'delete_products'

// Заказы
'view_orders', 'manage_orders'

// Отзывы
'view_reviews', 'moderate_reviews'

// Система
'manage_settings', 'manage_roles', 'view_logs', 'access_admin_panel'
```

## Middleware

### admin.ts
Проверяет права доступа к админ-панели. Перенаправляет на `/login` если нет доступа.

```typescript
definePageMeta({
  layout: 'admin',
  middleware: 'admin'
})
```

## Стилизация

### Tailwind CSS
Все компоненты используют Tailwind CSS для стилизации.

### Dark Mode
Полная поддержка темной темы через `useColorMode()`.

### Responsive Design
Все страницы адаптивны и работают на мобильных устройствах.

## Интеграция с Backend API

### Endpoints

#### Пользователи
- `GET /api/admin/users` - Список пользователей
- `GET /api/admin/users/:id` - Просмотр пользователя
- `POST /api/admin/users` - Создание пользователя
- `PUT /api/admin/users/:id` - Обновление пользователя
- `DELETE /api/admin/users/:id` - Удаление пользователя
- `POST /api/admin/users/:id/block` - Блокировка пользователя

#### Товары
- `GET /api/admin/products` - Список товаров
- `GET /api/admin/products/:id` - Просмотр товара
- `POST /api/admin/products` - Создание товара
- `PUT /api/admin/products/:id` - Обновление товара
- `DELETE /api/admin/products/:id` - Удаление товара

#### Заказы
- `GET /api/admin/orders` - Список заказов
- `GET /api/admin/orders/:id` - Просмотр заказа
- `PUT /api/admin/orders/:id/status` - Изменение статуса

#### Отзывы
- `GET /api/admin/reviews` - Список отзывов
- `POST /api/admin/reviews/:id/approve` - Одобрить отзыв
- `POST /api/admin/reviews/:id/reject` - Отклонить отзыв
- `DELETE /api/admin/reviews/:id` - Удалить отзыв

## Mock данные

В текущей версии используются mock данные для демонстрации функционала. При интеграции с реальным API необходимо заменить mock данные на реальные запросы через `useAdminApi`.

## Запуск

```bash
# Development
cd nuxt
npm run dev

# Build
npm run build

# Preview
npm run preview
```

## Архитектура

Проект следует best practices:
- **Composition API** для логики
- **TypeScript** для типобезопасности
- **Composables** для переиспользуемой логики
- **Component-based** архитектура
- **Responsive** дизайн
- **Dark mode** поддержка
- **Permission-based** доступ

## Поддержка

Для вопросов и предложений обращайтесь к техническому лидеру проекта.
