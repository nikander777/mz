# Руководство по использованию полиморфной структуры Favorites

## Обзор изменений

Таблица `favorites` была преобразована из монолитной структуры (только товары) в полиморфную, что позволяет добавлять в избранное любые типы сущностей.

### Структура ДО миграции:
```
favorites
├── id
├── user_id → users.id
├── product_id → products.id
├── created_at
└── updated_at

Индексы:
- UNIQUE(user_id, product_id)
- INDEX(user_id, created_at)
```

### Структура ПОСЛЕ миграции:
```
favorites
├── id
├── user_id → users.id
├── favoritable_id (INTEGER, NOT NULL)
├── favoritable_type (VARCHAR(255), NOT NULL)
├── created_at
└── updated_at

Индексы:
- UNIQUE(user_id, favoritable_type, favoritable_id)
- INDEX(favoritable_type, favoritable_id, created_at)
- INDEX(favoritable_type, favoritable_id)
- INDEX(user_id, created_at)
```

## Архитектурные решения

### 1. Почему полиморфная структура?

**Преимущества:**
- **Расширяемость**: Легко добавлять новые типы сущностей без изменения схемы БД
- **Переиспользование**: Единая логика работы с избранным для всех типов
- **Производительность**: Меньше JOIN'ов при получении избранного пользователя
- **Консистентность**: Централизованное хранение избранного

**Недостатки:**
- Невозможность использовать Foreign Keys (решается на уровне приложения)
- Немного сложнее написание запросов
- Требует дисциплины в именовании моделей

### 2. Индексная стратегия

#### Уникальный индекс `favorites_user_favoritable_unique`
```sql
UNIQUE(user_id, favoritable_type, favoritable_id)
```
**Цель**: Предотвращение дублирования избранного
**Применение**: Автоматически проверяется при INSERT

#### Индекс `favorites_favoritable_created_index`
```sql
INDEX(favoritable_type, favoritable_id, created_at)
```
**Цель**: Быстрое получение списка пользователей, добавивших в избранное
**Применение**: Страницы "Кто добавил в избранное" с сортировкой по дате
**Размер**: ~24 байта на запись (8 + 8 + 8)

#### Индекс `favorites_favoritable_index`
```sql
INDEX(favoritable_type, favoritable_id)
```
**Цель**: Быстрый подсчет популярности (COUNT запросы)
**Применение**: Витрины "Топ избранных", badge'и с количеством
**Размер**: ~16 байт на запись (8 + 8)

#### Индекс `favorites_user_created_index`
```sql
INDEX(user_id, created_at)
```
**Цель**: Быстрое получение избранного пользователя с сортировкой
**Применение**: Личная страница избранного
**Размер**: ~16 байт на запись (8 + 8)

### 3. Отсутствие Foreign Keys

**Решение**: Foreign Keys НЕ используются в полиморфных связях, т.к. `favoritable_id` может ссылаться на разные таблицы.

**Как обеспечивается целостность данных:**

1. **На уровне модели (События):**
```php
// В модели Product
protected static function booted()
{
    static::deleting(function ($product) {
        $product->favorites()->delete();
    });
}
```

2. **На уровне базы данных (Триггеры - опционально):**
```sql
-- Пример для SQLite
CREATE TRIGGER delete_product_favorites
AFTER DELETE ON products
BEGIN
    DELETE FROM favorites
    WHERE favoritable_type = 'App\Models\Product'
    AND favoritable_id = OLD.id;
END;
```

3. **Фоновые задачи очистки:**
```php
// Периодическая очистка "orphan" записей
Artisan::command('favorites:cleanup', function () {
    $orphans = DB::table('favorites')
        ->whereNotExists(function ($query) {
            $query->select(DB::raw(1))
                ->from('products')
                ->whereRaw('products.id = favorites.favoritable_id')
                ->where('favorites.favoritable_type', 'App\\Models\\Product');
        })
        ->delete();
})->purpose('Remove orphaned favorites');
```

## Использование в коде

### 1. Обновление модели Favorite

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\MorphTo;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Favorite extends Model
{
    protected $fillable = [
        'user_id',
        'favoritable_id',
        'favoritable_type',
    ];

    /**
     * Полиморфная связь - избранная сущность
     */
    public function favoritable(): MorphTo
    {
        return $this->morphTo();
    }

    /**
     * Пользователь, которому принадлежит избранное
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Scope: Получить избранное конкретного типа
     */
    public function scopeOfType($query, string $type)
    {
        return $query->where('favoritable_type', $type);
    }

    /**
     * Scope: Популярные сущности по количеству добавлений
     */
    public function scopePopular($query, string $type, int $limit = 10)
    {
        return $query->ofType($type)
            ->select('favoritable_id', DB::raw('count(*) as favorites_count'))
            ->groupBy('favoritable_id')
            ->orderByDesc('favorites_count')
            ->limit($limit);
    }
}
```

### 2. Обновление модели Product

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\MorphMany;

class Product extends Model
{
    /**
     * Все пользователи, добавившие товар в избранное
     */
    public function favorites(): MorphMany
    {
        return $this->morphMany(Favorite::class, 'favoritable');
    }

    /**
     * Проверка: добавлен ли товар в избранное конкретным пользователем
     */
    public function isFavoritedBy(?int $userId = null): bool
    {
        if (!$userId) {
            $userId = auth()->id();
        }

        return $this->favorites()
            ->where('user_id', $userId)
            ->exists();
    }

    /**
     * Количество добавлений в избранное (кэшируемое свойство)
     */
    public function getFavoritesCountAttribute(): int
    {
        return $this->favorites()->count();
    }

    /**
     * Каскадное удаление избранного при удалении товара
     */
    protected static function booted()
    {
        static::deleting(function ($product) {
            $product->favorites()->delete();
        });
    }
}
```

### 3. Обновление модели User

```php
<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Database\Eloquent\Relations\HasMany;

class User extends Authenticatable
{
    /**
     * Все избранное пользователя
     */
    public function favorites(): HasMany
    {
        return $this->hasMany(Favorite::class);
    }

    /**
     * Избранные товары
     */
    public function favoriteProducts()
    {
        return $this->morphedByMany(Product::class, 'favoritable', 'favorites')
            ->withTimestamps()
            ->orderByPivot('created_at', 'desc');
    }

    /**
     * Добавить сущность в избранное
     */
    public function addToFavorites(Model $model): Favorite
    {
        return $this->favorites()->firstOrCreate([
            'favoritable_type' => get_class($model),
            'favoritable_id' => $model->id,
        ]);
    }

    /**
     * Удалить из избранного
     */
    public function removeFromFavorites(Model $model): bool
    {
        return $this->favorites()
            ->where('favoritable_type', get_class($model))
            ->where('favoritable_id', $model->id)
            ->delete() > 0;
    }

    /**
     * Переключить состояние избранного (toggle)
     */
    public function toggleFavorite(Model $model): bool
    {
        $favorite = $this->favorites()
            ->where('favoritable_type', get_class($model))
            ->where('favoritable_id', $model->id)
            ->first();

        if ($favorite) {
            $favorite->delete();
            return false; // Удалено
        }

        $this->addToFavorites($model);
        return true; // Добавлено
    }
}
```

### 4. Примеры использования в контроллерах

#### Добавление товара в избранное
```php
public function store(Request $request, Product $product)
{
    $user = auth()->user();

    try {
        $favorite = $user->addToFavorites($product);

        return response()->json([
            'message' => 'Товар добавлен в избранное',
            'favorite' => $favorite,
        ], 201);
    } catch (\Illuminate\Database\UniqueConstraintViolationException $e) {
        return response()->json([
            'message' => 'Товар уже в избранном',
        ], 409);
    }
}
```

#### Удаление из избранного
```php
public function destroy(Product $product)
{
    $removed = auth()->user()->removeFromFavorites($product);

    if (!$removed) {
        return response()->json([
            'message' => 'Товар не найден в избранном',
        ], 404);
    }

    return response()->json([
        'message' => 'Товар удален из избранного',
    ], 200);
}
```

#### Toggle избранного
```php
public function toggle(Product $product)
{
    $added = auth()->user()->toggleFavorite($product);

    return response()->json([
        'message' => $added ? 'Товар добавлен в избранное' : 'Товар удален из избранного',
        'is_favorited' => $added,
        'favorites_count' => $product->favorites()->count(),
    ]);
}
```

#### Получение избранного пользователя
```php
public function index(Request $request)
{
    $user = auth()->user();

    $favorites = $user->favoriteProducts()
        ->with(['category', 'images'])
        ->paginate(20);

    return response()->json($favorites);
}
```

#### Популярные товары по избранному
```php
public function popular()
{
    $popularProducts = Favorite::popular('App\\Models\\Product', 10)
        ->with('favoritable')
        ->get()
        ->pluck('favoritable');

    return response()->json($popularProducts);
}
```

## Добавление новых типов в избранное

### Пример: Добавить артистов в избранное

1. **Модель Artist:**
```php
class Artist extends Model
{
    public function favorites(): MorphMany
    {
        return $this->morphMany(Favorite::class, 'favoritable');
    }

    protected static function booted()
    {
        static::deleting(function ($artist) {
            $artist->favorites()->delete();
        });
    }
}
```

2. **Добавить в User модель:**
```php
public function favoriteArtists()
{
    return $this->morphedByMany(Artist::class, 'favoritable', 'favorites')
        ->withTimestamps()
        ->orderByPivot('created_at', 'desc');
}
```

3. **Использование:**
```php
// Добавить артиста в избранное
auth()->user()->addToFavorites($artist);

// Получить избранных артистов
$favoriteArtists = auth()->user()->favoriteArtists;

// Популярные артисты
$popularArtists = Favorite::popular('App\\Models\\Artist', 10);
```

## Оптимизация производительности

### 1. Eager Loading для предотвращения N+1
```php
// Плохо (N+1 запросы)
$favorites = auth()->user()->favorites;
foreach ($favorites as $favorite) {
    echo $favorite->favoritable->name; // Каждый раз новый запрос
}

// Хорошо (2 запроса)
$favorites = auth()->user()->favorites()->with('favoritable')->get();
foreach ($favorites as $favorite) {
    echo $favorite->favoritable->name; // Уже загружено
}
```

### 2. Счетчики без загрузки моделей
```php
// Плохо (загружает все записи)
$count = auth()->user()->favorites->count();

// Хорошо (только COUNT запрос)
$count = auth()->user()->favorites()->count();
```

### 3. Кэширование популярных сущностей
```php
use Illuminate\Support\Facades\Cache;

public function popularProducts()
{
    return Cache::remember('popular_products', 3600, function () {
        return Favorite::popular('App\\Models\\Product', 20)
            ->with('favoritable')
            ->get()
            ->pluck('favoritable');
    });
}
```

### 4. Массовое добавление в избранное
```php
// Импорт избранного из другого источника
DB::transaction(function () use ($userId, $productIds) {
    $data = collect($productIds)->map(function ($productId) use ($userId) {
        return [
            'user_id' => $userId,
            'favoritable_type' => 'App\\Models\\Product',
            'favoritable_id' => $productId,
            'created_at' => now(),
            'updated_at' => now(),
        ];
    })->toArray();

    Favorite::insertOrIgnore($data); // Игнорирует дубликаты
});
```

## Тестирование

### Feature тесты
```php
use Tests\TestCase;
use App\Models\User;
use App\Models\Product;

class FavoriteTest extends TestCase
{
    public function test_user_can_add_product_to_favorites()
    {
        $user = User::factory()->create();
        $product = Product::factory()->create();

        $favorite = $user->addToFavorites($product);

        $this->assertDatabaseHas('favorites', [
            'user_id' => $user->id,
            'favoritable_type' => Product::class,
            'favoritable_id' => $product->id,
        ]);
    }

    public function test_cannot_add_duplicate_favorites()
    {
        $user = User::factory()->create();
        $product = Product::factory()->create();

        $user->addToFavorites($product);

        $this->expectException(\Illuminate\Database\UniqueConstraintViolationException::class);
        $user->addToFavorites($product);
    }

    public function test_favorites_deleted_when_product_deleted()
    {
        $user = User::factory()->create();
        $product = Product::factory()->create();

        $favorite = $user->addToFavorites($product);

        $product->delete();

        $this->assertDatabaseMissing('favorites', [
            'id' => $favorite->id,
        ]);
    }
}
```

## Мониторинг и обслуживание

### 1. Проверка orphan записей
```sql
-- Найти "orphan" избранное (товары удалены, но favorites остались)
SELECT COUNT(*) FROM favorites f
WHERE f.favoritable_type = 'App\Models\Product'
AND NOT EXISTS (
    SELECT 1 FROM products p
    WHERE p.id = f.favoritable_id
);
```

### 2. Анализ использования индексов (SQLite)
```sql
-- Проверить, используются ли индексы
EXPLAIN QUERY PLAN
SELECT * FROM favorites
WHERE favoritable_type = 'App\Models\Product'
AND favoritable_id = 123;
```

### 3. Статистика по типам
```sql
SELECT
    favoritable_type,
    COUNT(*) as total_favorites,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT favoritable_id) as unique_items
FROM favorites
GROUP BY favoritable_type;
```

## Миграция на продакшн

### Чеклист перед деплоем:
- [ ] Запустить `php artisan migrate --pretend` для проверки SQL
- [ ] Создать бэкап базы данных
- [ ] Проверить, что все модели обновлены
- [ ] Запустить миграцию: `php artisan migrate`
- [ ] Проверить работу приложения
- [ ] Мониторить логи ошибок первые 24 часа
- [ ] Проверить производительность запросов через `php artisan telescope`

### Rollback план:
```bash
# В случае проблем - откатить миграцию
php artisan migrate:rollback --step=1

# Восстановить из бэкапа (если необходимо)
```

## Заключение

Полиморфная структура `favorites` обеспечивает:
- ✅ Гибкость добавления новых типов сущностей
- ✅ Оптимальная производительность благодаря продуманным индексам
- ✅ Целостность данных через model events
- ✅ Простота использования через helper методы
- ✅ Полная обратимость миграции

При возникновении проблем или вопросов обращайтесь к техническому лидеру команды.
