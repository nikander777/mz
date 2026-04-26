# HasDataTable Trait - Руководство по использованию

## Описание

Trait `HasDataTable` предоставляет готовый функционал для работы с таблицами данных в Laravel контроллерах.

**Основной функционал:**
- Фильтрация данных (поиск, статус, даты)
- Сортировка с валидацией полей
- Пагинация с ограничениями
- Экспорт в CSV и Excel

## Установка

Trait использует пакет Laravel Excel, который уже установлен:

```bash
composer require maatwebsite/excel
```

## Базовое использование

### 1. Подключение trait в контроллере

```php
use App\Traits\HasDataTable;

class OrderController extends Controller
{
    use HasDataTable;

    public function __construct()
    {
        // Определяем поля для поиска
        $this->setSearchableFields([
            'order_number',
            'customer_name',
            'customer_email',
        ]);

        // Опционально: определяем поля для сортировки
        $this->setSortableFields([
            'id',
            'order_number',
            'total_amount',
            'status',
            'created_at',
        ]);
    }
}
```

### 2. Использование в методе index

```php
public function index(Request $request)
{
    $query = Order::query();

    $options = [
        'filters' => [
            'search' => $request->input('search'),
            'status' => $request->input('status'),
            'date_from' => $request->input('date_from'),
            'date_to' => $request->input('date_to'),
        ],
        'sort_field' => $request->input('sort_field', 'created_at'),
        'sort_order' => $request->input('sort_order', 'desc'),
        'per_page' => (int) $request->input('per_page', 15),
    ];

    return $this->getDataTable($query, $options);
}
```

## Фильтрация

### Встроенные фильтры

**Поиск (search):**
- Ищет по полям, указанным в `searchableFields`
- Использует LIKE с подстановочными знаками
- Работает с OR логикой между полями

**Статус (status):**
- Точное совпадение по полю `status`

**Диапазон дат (date_from, date_to):**
- Фильтрация по полю `created_at`
- Работает на уровне даты (без времени)

### Кастомные фильтры

Для добавления собственных фильтров создайте метод `applyCustomFilters`:

```php
protected function applyCustomFilters($query, array $filters): void
{
    // Фильтр по диапазону сумм
    if (!empty($filters['min_amount'])) {
        $query->where('total_amount', '>=', $filters['min_amount']);
    }

    if (!empty($filters['max_amount'])) {
        $query->where('total_amount', '<=', $filters['max_amount']);
    }

    // Фильтр по связанным данным
    if (!empty($filters['payment_method'])) {
        $query->whereHas('payments', function ($q) use ($filters) {
            $q->where('payment_method', $filters['payment_method']);
        });
    }
}
```

## Сортировка

**Параметры:**
- `sort_field` - поле для сортировки (должно быть в `sortableFields`)
- `sort_order` - направление: `asc` или `desc`

**Валидация:**
- Проверяет, что поле доступно для сортировки
- Проверяет корректность направления

**По умолчанию:**
- Поле: `created_at`
- Направление: `desc`

## Пагинация

**Параметры:**
- `per_page` - количество элементов на странице

**Ограничения:**
- Минимум: 1
- Максимум: 100
- По умолчанию: 15

## Экспорт данных

### Экспорт в CSV

```php
$options = [
    'export' => 'csv',
    'export_columns' => ['id', 'order_number', 'customer_name', 'total_amount'],
    'export_filename' => 'orders_export',
];

return $this->getDataTable($query, $options);
```

### Экспорт в Excel

```php
$options = [
    'export' => 'excel',
    'export_columns' => ['id', 'order_number', 'customer_name', 'total_amount'],
    'export_filename' => 'orders_export',
];

return $this->getDataTable($query, $options);
```

## Примеры API запросов

### Получение списка с фильтрами

```
GET /api/orders?search=John&status=completed&per_page=25&sort_field=total_amount&sort_order=desc
```

### Фильтрация по датам

```
GET /api/orders?date_from=2025-01-01&date_to=2025-12-31
```

### Экспорт в Excel

```
GET /api/orders/export?export=excel&status=completed
```

## Методы trait

### Публичные методы для использования

- `getDataTable(Builder $query, array $options)` - главный метод

### Защищенные методы (можно переопределить)

- `applyFilters(Builder $query, array $filters)` - применить фильтры
- `applySort(Builder $query, ?string $sortField, ?string $sortOrder)` - применить сортировку
- `paginate(Builder $query, ?int $perPage)` - применить пагинацию
- `exportToCSV(Builder $query, array $columns, string $filename)` - экспорт CSV
- `exportToExcel(Builder $query, array $columns, string $filename)` - экспорт Excel
- `applyCustomFilters($query, array $filters)` - кастомные фильтры (опционально)

### Методы настройки

- `setSearchableFields(array $fields)` - установить поля для поиска
- `setSortableFields(array $fields)` - установить поля для сортировки
- `getSearchableFields()` - получить поля для поиска
- `getSortableFields()` - получить поля для сортировки

## Безопасность

Trait обеспечивает защиту от:

1. **SQL Injection** - использует параметризованные запросы Laravel
2. **Невалидные поля сортировки** - валидация через whitelist
3. **Превышение лимитов** - ограничение `per_page` до 100
4. **Невалидные направления сортировки** - только `asc` и `desc`

## Интеграция с Inertia.js

```php
use Inertia\Inertia;

public function index(Request $request)
{
    $query = Order::query()->with(['items', 'customer']);

    $orders = $this->getDataTable($query, [
        'filters' => $request->only(['search', 'status', 'date_from', 'date_to']),
        'sort_field' => $request->input('sort_field', 'created_at'),
        'sort_order' => $request->input('sort_order', 'desc'),
        'per_page' => (int) $request->input('per_page', 15),
    ]);

    return Inertia::render('Orders/Index', [
        'orders' => $orders,
        'filters' => $request->only(['search', 'status', 'date_from', 'date_to']),
    ]);
}
```

## Пример полного контроллера

См. файл `/app/Http/Controllers/ExampleDataTableController.php`
