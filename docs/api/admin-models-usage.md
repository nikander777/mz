# Руководство по использованию моделей админ-панели

## Обзор созданных моделей

Созданы следующие модели для системы администрирования MUZILLA:

1. **AdminActivityLog** - Логирование действий администраторов
2. **AuditTrail** - Универсальный аудит изменений моделей
3. **SystemSetting** - Управление настройками системы с кэшированием
4. **AdminNotification** - Система уведомлений для администраторов
5. **AdminDashboardMetric** - Кэш метрик дашборда
6. **Auditable (Trait)** - Трейт для автоматического аудита моделей

---

## 1. AdminActivityLog

### Основные возможности
- Логирование всех действий администраторов
- Сохранение технической информации (IP, User-Agent, URL)
- Отслеживание изменений с JSON данными
- Статусы выполнения (success, failed, warning)

### Примеры использования

```php
use App\Models\AdminActivityLog;

// Простое логирование действия
AdminActivityLog::log([
    'action' => AdminActivityLog::ACTION_CREATE,
    'entity_type' => Product::class,
    'entity_id' => $product->id,
    'entity_display' => $product->name,
    'description' => 'Создан новый товар',
    'changes' => $product->toArray(),
]);

// Логирование успешного действия
AdminActivityLog::logSuccess(AdminActivityLog::ACTION_UPDATE, [
    'entity_type' => User::class,
    'entity_id' => $user->id,
    'entity_display' => $user->name,
    'description' => 'Обновлён профиль пользователя',
    'changes' => $user->getChanges(),
]);

// Логирование ошибки
AdminActivityLog::logFailure(
    AdminActivityLog::ACTION_DELETE,
    'Невозможно удалить товар с активными заказами',
    [
        'entity_type' => Product::class,
        'entity_id' => $product->id,
    ]
);

// Получение логов
$logs = AdminActivityLog::query()
    ->byAdmin(auth()->id())
    ->byAction(AdminActivityLog::ACTION_CREATE)
    ->lastDays(7)
    ->get();

// Фильтрация по сущности
$productLogs = AdminActivityLog::query()
    ->byEntity(Product::class, $product->id)
    ->successful()
    ->get();
```

---

## 2. AuditTrail

### Основные возможности
- Polymorphic отношения к любым моделям
- Автоматическая запись изменений через трейт Auditable
- Хранение старых и новых значений полей
- Поддержка тегов для группировки

### Примеры использования

```php
use App\Models\AuditTrail;

// Ручное создание аудита
AuditTrail::audit(
    $product,
    AuditTrail::EVENT_UPDATED,
    auth()->user(),
    ['price' => 1000],
    ['price' => 1500]
);

// Получение истории изменений модели
$audits = $product->auditTrails()
    ->with('user')
    ->latest()
    ->get();

// Последнее изменение
$lastAudit = $product->latestAudit();

// Фильтрация по событиям
$creations = AuditTrail::query()
    ->byModel(Product::class)
    ->created()
    ->get();

// Административные действия
$adminActions = AuditTrail::query()
    ->adminActions()
    ->dateRange('2024-01-01', '2024-12-31')
    ->get();

// Получение конкретного изменения
$priceChange = $lastAudit->getFieldChange('price');
// ['old' => 1000, 'new' => 1500]
```

---

## 3. Использование трейта Auditable

### Добавление в модель

```php
use App\Traits\Auditable;

class Product extends Model
{
    use Auditable;

    // Указать поля для аудита (опционально)
    public function getAuditableFields(): array
    {
        return ['name', 'price', 'stock', 'status'];
    }

    // Исключить чувствительные поля (опционально)
    public function getAuditExcludeFields(): array
    {
        return ['internal_notes', 'cost_price'];
    }

    // Указать события для аудита (опционально)
    public function getAuditEvents(): array
    {
        return ['created', 'updated', 'deleted'];
    }

    // Добавить теги (опционально)
    public function getAuditTags(string $event): array
    {
        return ['product', $this->category];
    }
}
```

### Автоматическая запись

```php
// После добавления трейта все изменения записываются автоматически

$product = Product::create([
    'name' => 'Новый товар',
    'price' => 1000,
]);
// Автоматически создаётся запись AuditTrail с event='created'

$product->update(['price' => 1500]);
// Автоматически создаётся запись AuditTrail с event='updated'
// с сохранением старого (1000) и нового (1500) значения

$product->delete();
// Автоматически создаётся запись AuditTrail с event='deleted'
```

---

## 4. SystemSetting

### Основные возможности
- Хранение настроек с автоопределением типов
- Кэширование значений (TTL 1 час)
- Валидация значений
- Группировка настроек
- Публичные/приватные настройки

### Примеры использования

```php
use App\Models\SystemSetting;

// Получение настройки
$siteName = SystemSetting::get('site_name', 'MUZILLA');
$maxFileSize = SystemSetting::get('max_file_size', 10);

// Установка настройки
SystemSetting::set('site_name', 'MUZILLA Market', 'general', [
    'label' => 'Название сайта',
    'description' => 'Отображается в шапке сайта',
    'is_public' => true,
    'is_editable' => true,
]);

// Настройка с валидацией
SystemSetting::set('max_upload_size', 50, 'files', [
    'label' => 'Максимальный размер файла (MB)',
    'validation_rules' => ['integer', 'min:1', 'max:100'],
]);

// Получение группы настроек
$emailSettings = SystemSetting::group('email');
// ['smtp_host' => 'smtp.gmail.com', 'smtp_port' => 587, ...]

// Массовая установка
SystemSetting::setMultiple([
    'smtp_host' => 'smtp.gmail.com',
    'smtp_port' => 587,
    'smtp_user' => 'noreply@muzilla.ru',
], 'email');

// Публичные настройки (для API)
$publicSettings = SystemSetting::getPublic();

// Работа с boolean
SystemSetting::set('maintenance_mode', true, 'system');
$isMaintenanceMode = SystemSetting::get('maintenance_mode'); // true

// Работа с JSON
SystemSetting::set('social_links', [
    'vk' => 'https://vk.com/muzilla',
    'telegram' => 'https://t.me/muzilla',
], 'social');

// Очистка кэша
SystemSetting::clearAllCache();
```

---

## 5. AdminNotification

### Основные возможности
- Уведомления для конкретных администраторов или ролей
- Приоритеты (low, normal, high, urgent)
- Связь с сущностями системы
- Срок действия уведомлений
- Действия (action_url)

### Примеры использования

```php
use App\Models\AdminNotification;

// Создать уведомление для администратора
AdminNotification::forAdmin(
    $adminId,
    AdminNotification::TYPE_ORDER_COMPLAINT,
    'Новая жалоба на заказ',
    'Пользователь оставил жалобу на заказ #12345',
    [
        'priority' => AdminNotification::PRIORITY_HIGH,
        'related_type' => Order::class,
        'related_id' => $order->id,
        'related_url' => route('admin.orders.show', $order),
        'action_url' => route('admin.complaints.review', $complaint),
        'action_label' => 'Рассмотреть жалобу',
    ]
);

// Уведомление для всей роли
AdminNotification::forRole(
    'admin',
    AdminNotification::TYPE_SECURITY_ALERT,
    'Подозрительная активность',
    'Обнаружены множественные попытки входа с неизвестного IP',
    [
        'priority' => AdminNotification::PRIORITY_URGENT,
    ]
);

// Получить непрочитанные уведомления
$unread = AdminNotification::query()
    ->forUser(auth()->user())
    ->unread()
    ->activeNotExpired()
    ->orderByPriority()
    ->get();

// Количество непрочитанных
$count = AdminNotification::unreadCountForUser(auth()->user());

// Отметить как прочитанное
$notification->markAsRead();

// Отметить все как прочитанные
AdminNotification::markAllAsReadForUser(auth()->user());

// Фильтрация по приоритету
$urgent = AdminNotification::query()
    ->forUser(auth()->user())
    ->urgent()
    ->get();

// Архивирование
$notification->archive();
```

---

## 6. AdminDashboardMetric

### Основные возможности
- Кэширование метрик по датам
- Финальные и предварительные данные
- Сравнение периодов
- Агрегация (sum, avg)
- Автоматическая очистка старых данных

### Примеры использования

```php
use App\Models\AdminDashboardMetric;

// Установить метрику
AdminDashboardMetric::setMetric(
    today(),
    AdminDashboardMetric::TYPE_TOTAL_SALES,
    125000.50,
    ['orders_count' => 45],
    false // предварительные данные
);

// Получить метрику
$sales = AdminDashboardMetric::getMetric(
    today(),
    AdminDashboardMetric::TYPE_TOTAL_SALES
);

// Массовая установка метрик
AdminDashboardMetric::setMultiple(today(), [
    AdminDashboardMetric::TYPE_TOTAL_SALES => 125000.50,
    AdminDashboardMetric::TYPE_NEW_USERS => 12,
    AdminDashboardMetric::TYPE_NEW_ORDERS => 45,
]);

// Метрики за период
$metrics = AdminDashboardMetric::getMetricsForPeriod(
    now()->subDays(7),
    now(),
    AdminDashboardMetric::TYPE_REVENUE
);

// Сумма за период
$totalRevenue = AdminDashboardMetric::sumForPeriod(
    now()->startOfMonth(),
    now()->endOfMonth(),
    AdminDashboardMetric::TYPE_REVENUE
);

// Среднее значение
$avgOrderValue = AdminDashboardMetric::avgForPeriod(
    now()->subDays(30),
    now(),
    AdminDashboardMetric::TYPE_AVG_ORDER_VALUE
);

// Сравнение с предыдущим периодом
$comparison = AdminDashboardMetric::compareWithPreviousPeriod(
    now()->startOfWeek(),
    now()->endOfWeek(),
    AdminDashboardMetric::TYPE_REVENUE
);
/*
[
    'current' => 250000,
    'previous' => 200000,
    'change' => [
        'value' => 50000,
        'percentage' => 25.0,
        'trend' => 'up'
    ]
]
*/

// Получить изменение метрики
$change = AdminDashboardMetric::getChange(
    now()->subDay(),
    now(),
    AdminDashboardMetric::TYPE_NEW_USERS
);

// Очистка старых метрик (старше 90 дней)
AdminDashboardMetric::cleanOldMetrics(90);

// Метрики за сегодня
$todayMetrics = AdminDashboardMetric::today()
    ->get()
    ->keyBy('metric_type');

// Финальные метрики текущего месяца
$finalMetrics = AdminDashboardMetric::currentMonth()
    ->final()
    ->get();
```

---

## Интеграция в контроллерах

### Пример контроллера с логированием

```php
use App\Models\AdminActivityLog;
use App\Models\Product;

class ProductController extends Controller
{
    public function store(Request $request)
    {
        try {
            $product = Product::create($request->validated());

            AdminActivityLog::logSuccess(AdminActivityLog::ACTION_CREATE, [
                'entity_type' => Product::class,
                'entity_id' => $product->id,
                'entity_display' => $product->name,
                'description' => 'Создан новый товар',
                'changes' => $product->toArray(),
            ]);

            return response()->json($product, 201);
        } catch (\Exception $e) {
            AdminActivityLog::logFailure(
                AdminActivityLog::ACTION_CREATE,
                $e->getMessage(),
                ['entity_type' => Product::class]
            );

            throw $e;
        }
    }
}
```

### Пример использования уведомлений

```php
use App\Models\AdminNotification;
use App\Models\Order;

class OrderController extends Controller
{
    public function complaint(Request $request, Order $order)
    {
        $complaint = $order->complaints()->create($request->validated());

        // Уведомить всех администраторов
        AdminNotification::forRole(
            'admin',
            AdminNotification::TYPE_ORDER_COMPLAINT,
            "Жалоба на заказ #{$order->id}",
            $request->message,
            [
                'priority' => AdminNotification::PRIORITY_HIGH,
                'related_type' => Order::class,
                'related_id' => $order->id,
                'related_url' => route('admin.orders.show', $order),
            ]
        );

        return response()->json($complaint, 201);
    }
}
```

---

## Лучшие практики

### 1. AdminActivityLog
- Логируйте все критичные действия администраторов
- Используйте денормализацию (admin_name, entity_display) для сохранения истории
- Регулярно архивируйте старые логи

### 2. AuditTrail
- Используйте трейт Auditable для автоматического аудита
- Исключайте чувствительные поля через getAuditExcludeFields()
- Добавляйте теги для удобной фильтрации

### 3. SystemSetting
- Группируйте связанные настройки
- Используйте валидацию для критичных настроек
- Помечайте публичные настройки is_public=true
- Очищайте кэш при необходимости

### 4. AdminNotification
- Используйте правильные приоритеты
- Устанавливайте срок действия для временных уведомлений
- Связывайте с сущностями через related_type/related_id
- Добавляйте action_url для быстрых действий

### 5. AdminDashboardMetric
- Устанавливайте is_final=true для завершённых периодов
- Регулярно очищайте старые метрики
- Используйте additional_data для breakdown данных
- Кэшируйте тяжёлые расчёты

---

## Миграции

Все таблицы созданы миграцией:
```
database/migrations/2025_10_03_000000_create_admin_panel_tables.php
```

Запуск миграций:
```bash
php artisan migrate
```

---

## Заключение

Созданные модели предоставляют полноценную инфраструктуру для:
- Логирования действий администраторов
- Аудита изменений данных
- Управления настройками системы
- Системы уведомлений
- Кэширования метрик дашборда

Все модели используют строгую типизацию PHP 8.2, включают PHPDoc комментарии и следуют лучшим практикам Laravel 12.
