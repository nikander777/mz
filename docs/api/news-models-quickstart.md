# Модели системы новостей - Краткое руководство

## Созданные файлы

### Модели (`/app/Models/`)
- `News.php` - основная модель новости
- `NewsCategory.php` - категории новостей (иерархическая структура)
- `NewsTag.php` - теги с автоматическим подсчетом использований
- `NewsImage.php` - галерея изображений новости

### Observer (`/app/Observers/`)
- `NewsObserver.php` - автоматическая генерация slug и расчет reading_time

### API Resources (`/app/Http/Resources/`)
- `NewsResource.php`
- `NewsCategoryResource.php`
- `NewsTagResource.php`
- `NewsImageResource.php`

### Form Requests (`/app/Http/Requests/News/`)
- `StoreNewsRequest.php` - валидация создания новости
- `UpdateNewsRequest.php` - валидация обновления новости

### Конфигурация
- `AppServiceProvider.php` - зарегистрирован NewsObserver

## Быстрый старт

### 1. Создание новости

```php
use App\Models\News;

$news = News::create([
    'title' => 'Заголовок новости',
    'content' => 'Содержание новости...',
    'author_id' => auth()->id(),
    'status' => News::STATUS_PUBLISHED,
]);

// slug и reading_time генерируются автоматически!
```

### 2. Добавление категорий и тегов

```php
// Категории
$news->categories()->attach([1, 2, 3]);

// Теги (с автоматическим подсчетом usage_count)
$news->syncTagsWithCount([1, 2, 3]);
```

### 3. Получение опубликованных новостей

```php
$publishedNews = News::published()
    ->with(['author', 'categories', 'tags'])
    ->recent()
    ->paginate(10);
```

### 4. API Response

```php
use App\Http\Resources\NewsResource;

return NewsResource::collection($publishedNews);
```

## Ключевые особенности

### Автоматические функции

1. **Slug** - генерируется из title при создании
2. **Reading Time** - рассчитывается из content (200 слов/минута)
3. **Published At** - автоматически устанавливается при публикации
4. **Sort Order** - автоматически для категорий и изображений
5. **Usage Count** - автоматически для тегов

### Query Scopes

```php
// Новости
News::published();
News::draft();
News::recent();
News::popular();
News::inCategory($id);
News::withTag($id);

// Категории
NewsCategory::active();
NewsCategory::sorted();
NewsCategory::parents();

// Теги
NewsTag::popular(10);
NewsTag::used();
```

### Статусы новостей

```php
News::STATUS_DRAFT      // 'draft'
News::STATUS_PUBLISHED  // 'published'
News::STATUS_ARCHIVED   // 'archived'
```

## Полная документация

Подробная документация со всеми методами, примерами и best practices:
📄 `news-models.md`

## Структура БД

Таблицы созданы миграциями в `/database/migrations/`:
- `news_categories`
- `news_tags`
- `news`
- `news_images`
- `category_news` (pivot)
- `news_tag` (pivot)
- `related_news` (pivot)

## Следующие шаги

1. Создать контроллеры (NewsController, NewsCategoryController)
2. Добавить роуты в `routes/web.php` или `routes/api.php`
3. Создать Policy для управления доступом
4. Добавить фабрики и сидеры для тестирования
5. Создать тесты (Pest)

## Пример контроллера

```php
namespace App\Http\Controllers;

use App\Models\News;
use App\Http\Requests\News\StoreNewsRequest;
use App\Http\Requests\News\UpdateNewsRequest;
use App\Http\Resources\NewsResource;

class NewsController extends Controller
{
    public function index()
    {
        $news = News::published()
            ->with(['author', 'categories', 'tags'])
            ->recent()
            ->paginate(10);

        return NewsResource::collection($news);
    }

    public function show(News $news)
    {
        $news->load(['author', 'categories', 'tags', 'images', 'relatedNews']);
        $news->incrementViews();

        return new NewsResource($news);
    }

    public function store(StoreNewsRequest $request)
    {
        $news = News::create($request->validated());

        if ($request->has('category_ids')) {
            $news->categories()->attach($request->category_ids);
        }

        if ($request->has('tag_ids')) {
            $news->syncTagsWithCount($request->tag_ids);
        }

        return new NewsResource($news);
    }

    public function update(UpdateNewsRequest $request, News $news)
    {
        $news->update($request->validated());

        if ($request->has('category_ids')) {
            $news->categories()->sync($request->category_ids);
        }

        if ($request->has('tag_ids')) {
            $news->syncTagsWithCount($request->tag_ids);
        }

        return new NewsResource($news);
    }

    public function destroy(News $news)
    {
        $news->delete();

        return response()->json(['message' => 'Новость удалена']);
    }
}
```

## Проверка

Все файлы проверены на синтаксические ошибки PHP ✅
Автозагрузка Composer обновлена ✅
Observer зарегистрирован ✅

---

**Дата создания:** 26 октября 2025
**Laravel версия:** 12
**PHP версия:** 8.2+
