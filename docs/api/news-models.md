# Документация по моделям системы новостей

## Обзор

Система новостей состоит из четырех основных моделей Laravel 12:

1. **News** - основная модель новости
2. **NewsCategory** - категории новостей с иерархической структурой
3. **NewsTag** - теги для маркировки новостей
4. **NewsImage** - галерея изображений для новостей

Все модели используют современные паттерны Laravel 12, строгую типизацию PHP 8.2+ и следуют принципам SOLID.

## Модели

### News

**Файл:** `/app/Models/News.php`

Основная модель новости с полной поддержкой статусов, категорий, тегов и изображений.

#### Константы статусов

```php
News::STATUS_DRAFT      // 'draft' - черновик
News::STATUS_PUBLISHED  // 'published' - опубликовано
News::STATUS_ARCHIVED   // 'archived' - архив
```

#### Основные поля

- `title` - заголовок новости
- `slug` - URL-friendly идентификатор (генерируется автоматически)
- `excerpt` - краткое описание
- `content` - полное содержание
- `author_id` - ID автора (User)
- `status` - статус публикации
- `featured_image` - главное изображение
- `seo_meta` - SEO метаданные (JSON)
- `reading_time` - время чтения в минутах (рассчитывается автоматически)
- `views_count` - счетчик просмотров
- `published_at` - дата публикации

#### Отношения

```php
$news->author;           // BelongsTo User
$news->categories;       // BelongsToMany NewsCategory
$news->tags;             // BelongsToMany NewsTag
$news->images;           // HasMany NewsImage
$news->relatedNews;      // BelongsToMany News (self-referencing)
```

#### Query Scopes

```php
News::published();                    // Только опубликованные
News::draft();                        // Черновики
News::archived();                     // Архивные
News::recent();                       // Сортировка по дате (новые первые)
News::popular();                      // Сортировка по просмотрам
News::withFeaturedImage();           // С главным изображением
News::byAuthor($authorId);           // Новости автора
News::inCategory($categoryId);       // Новости категории
News::withTag($tagId);               // Новости с тегом
```

#### Методы

```php
// Увеличить просмотры
$news->incrementViews();

// Рассчитать время чтения
$readingTime = $news->calculateReadingTime(); // int (минуты)

// Генерировать slug
$slug = $news->generateSlug();

// Проверки статуса
$news->isPublished();  // bool
$news->isDraft();      // bool
$news->isArchived();   // bool

// Изменение статуса
$news->publish();      // Опубликовать
$news->archive();      // В архив

// Синхронизация тегов с автоматическим подсчетом
$news->syncTagsWithCount([1, 2, 3]);
```

#### Атрибуты

```php
$news->url;                      // URL новости
$news->reading_time_formatted;   // "5 минут"
```

#### Пример использования

```php
use App\Models\News;

// Создание новости
$news = News::create([
    'title' => 'Моя новость',
    'content' => 'Содержание новости...',
    'author_id' => auth()->id(),
    'status' => News::STATUS_DRAFT,
]);

// Slug генерируется автоматически
echo $news->slug; // "moya-novost"

// Reading time рассчитывается автоматически
echo $news->reading_time; // 3 (минуты)

// Добавление категорий
$news->categories()->attach([1, 2]);

// Синхронизация тегов (с автоматическим подсчетом usage_count)
$news->syncTagsWithCount([1, 2, 3]);

// Публикация
$news->publish();

// Получение опубликованных новостей
$publishedNews = News::published()
    ->with(['author', 'categories', 'tags'])
    ->recent()
    ->paginate(10);
```

### NewsCategory

**Файл:** `/app/Models/NewsCategory.php`

Иерархическая модель категорий новостей с поддержкой вложенности.

#### Основные поля

- `name` - название категории
- `slug` - URL-friendly идентификатор
- `description` - описание
- `parent_id` - ID родительской категории
- `sort_order` - порядок сортировки (устанавливается автоматически)
- `is_active` - флаг активности

#### Отношения

```php
$category->parent;           // BelongsTo NewsCategory
$category->children;         // HasMany NewsCategory
$category->activeChildren(); // HasMany (только активные)
$category->news;             // BelongsToMany News
$category->publishedNews();  // BelongsToMany (только опубликованные)
```

#### Query Scopes

```php
NewsCategory::active();      // Только активные
NewsCategory::sorted();      // Сортировка по порядку
NewsCategory::parents();     // Только родительские (верхний уровень)
NewsCategory::children();    // Только дочерние
NewsCategory::withNews();    // С новостями
```

#### Методы

```php
// Проверки структуры
$category->isParent();      // bool
$category->isChild();       // bool
$category->hasChildren();   // bool

// Получение иерархии
$children = $category->getAllChildren();  // Collection всех дочерних
$path = $category->getPath();             // Collection пути от корня
```

#### Атрибуты

```php
$category->path_name;            // "Родитель > Категория"
$category->news_count;           // Количество новостей
$category->published_news_count; // Количество опубликованных
$category->url;                  // URL категории
```

#### Пример использования

```php
use App\Models\NewsCategory;

// Создание категории
$category = NewsCategory::create([
    'name' => 'Технологии',
    'slug' => 'tehnologii',
    'is_active' => true,
]);

// Создание подкатегории
$subCategory = NewsCategory::create([
    'name' => 'AI и ML',
    'slug' => 'ai-ml',
    'parent_id' => $category->id,
]);

// Получение активных категорий верхнего уровня
$mainCategories = NewsCategory::active()
    ->parents()
    ->sorted()
    ->with('activeChildren')
    ->get();

// Работа с иерархией
$path = $subCategory->getPath(); // [Технологии, AI и ML]
$pathName = $subCategory->path_name; // "Технологии > AI и ML"
```

### NewsTag

**Файл:** `/app/Models/NewsTag.php`

Модель тега с автоматическим подсчетом использований.

#### Основные поля

- `name` - название тега
- `slug` - URL-friendly идентификатор
- `description` - описание
- `usage_count` - количество использований (обновляется автоматически)

#### Отношения

```php
$tag->news;            // BelongsToMany News
$tag->publishedNews(); // BelongsToMany (только опубликованные)
```

#### Query Scopes

```php
NewsTag::popular($limit);   // Популярные теги
NewsTag::used();            // С использованиями
NewsTag::unused();          // Без использований
NewsTag::search($query);    // Поиск по имени
```

#### Методы

```php
// Управление счетчиком
$tag->incrementUsageCount();      // +1
$tag->decrementUsageCount();      // -1
$tag->recalculateUsageCount();    // Пересчитать
```

#### Атрибуты

```php
$tag->news_count;            // Количество новостей
$tag->published_news_count;  // Количество опубликованных
$tag->url;                   // URL тега
```

#### Пример использования

```php
use App\Models\NewsTag;

// Создание тега
$tag = NewsTag::create([
    'name' => 'Laravel',
    'slug' => 'laravel',
    'description' => 'PHP фреймворк',
]);

// Получение популярных тегов
$popularTags = NewsTag::popular(10)->get();

// Поиск тегов
$searchResults = NewsTag::search('laravel')->get();

// Автоматический подсчет происходит через метод syncTagsWithCount() в News
```

### NewsImage

**Файл:** `/app/Models/NewsImage.php`

Модель изображения для галереи новости.

#### Основные поля

- `news_id` - ID новости
- `path` - путь к файлу
- `disk` - диск хранения (по умолчанию 'public')
- `filename` - имя файла
- `mime_type` - MIME тип
- `size` - размер файла в байтах
- `width` - ширина изображения
- `height` - высота изображения
- `alt_text` - альтернативный текст
- `title` - заголовок
- `caption` - подпись
- `sort_order` - порядок в галерее (устанавливается автоматически)

#### Отношения

```php
$image->news;  // BelongsTo News
```

#### Query Scopes

```php
NewsImage::sorted();  // Сортировка по порядку
```

#### Методы

```php
// Работа с файлами
$image->exists();       // bool - проверка существования
$image->deleteFile();   // bool - удаление файла

// Проверки ориентации
$image->isPortrait();   // bool
$image->isLandscape();  // bool
$image->isSquare();     // bool
```

#### Атрибуты

```php
$image->url;                  // Полный URL изображения
$image->full_path;            // Полный путь в файловой системе
$image->file_size_formatted;  // "1.5 MB"
$image->dimensions;           // "1920x1080"
$image->aspect_ratio;         // 1.78
```

#### Пример использования

```php
use App\Models\NewsImage;

// Создание изображения
$image = NewsImage::create([
    'news_id' => $news->id,
    'path' => 'news/image.jpg',
    'disk' => 'public',
    'filename' => 'image.jpg',
    'mime_type' => 'image/jpeg',
    'size' => 150000,
    'width' => 1920,
    'height' => 1080,
    'alt_text' => 'Описание изображения',
]);

// Получение изображений новости
$images = $news->images()->sorted()->get();

// Проверка ориентации
if ($image->isLandscape()) {
    // Обработка горизонтального изображения
}
```

## API Resources

### NewsResource

**Файл:** `/app/Http/Resources/NewsResource.php`

```php
use App\Http\Resources\NewsResource;

// Одна новость
return new NewsResource($news->load(['author', 'categories', 'tags']));

// Коллекция
return NewsResource::collection($news);
```

### NewsCategoryResource

**Файл:** `/app/Http/Resources/NewsCategoryResource.php`

```php
use App\Http\Resources\NewsCategoryResource;

return new NewsCategoryResource($category->load(['parent', 'children']));
```

### NewsTagResource

**Файл:** `/app/Http/Resources/NewsTagResource.php`

```php
use App\Http\Resources\NewsTagResource;

return NewsTagResource::collection($tags);
```

### NewsImageResource

**Файл:** `/app/Http/Resources/NewsImageResource.php`

```php
use App\Http\Resources\NewsImageResource;

return NewsImageResource::collection($images);
```

## Form Requests

### StoreNewsRequest

**Файл:** `/app/Http/Requests/News/StoreNewsRequest.php`

Валидация при создании новости.

```php
use App\Http\Requests\News\StoreNewsRequest;

public function store(StoreNewsRequest $request)
{
    $validated = $request->validated();
    // author_id устанавливается автоматически
    // published_at устанавливается для опубликованных
}
```

### UpdateNewsRequest

**Файл:** `/app/Http/Requests/News/UpdateNewsRequest.php`

Валидация при обновлении новости.

```php
use App\Http\Requests\News\UpdateNewsRequest;

public function update(UpdateNewsRequest $request, News $news)
{
    $validated = $request->validated();
    // Проверка авторства или прав администратора
}
```

## Observer

**Файл:** `/app/Observers/NewsObserver.php`

NewsObserver автоматически:

1. Генерирует slug из title (если не указан)
2. Рассчитывает reading_time при создании/обновлении
3. Устанавливает published_at при публикации
4. Логирует все операции
5. Очищает связи при удалении

Observer зарегистрирован в `AppServiceProvider`:

```php
News::observe(NewsObserver::class);
```

## Примеры использования

### Создание полной новости

```php
use App\Models\News;
use Illuminate\Support\Facades\DB;

DB::transaction(function () {
    // Создание новости
    $news = News::create([
        'title' => 'Новый релиз Laravel 12',
        'excerpt' => 'Краткое описание...',
        'content' => 'Полное содержание...',
        'author_id' => auth()->id(),
        'status' => News::STATUS_PUBLISHED,
        'featured_image' => 'news/featured.jpg',
        'seo_meta' => [
            'title' => 'SEO заголовок',
            'description' => 'SEO описание',
            'keywords' => 'laravel, php, framework',
        ],
    ]);

    // Добавление категорий
    $news->categories()->attach([1, 2]);

    // Синхронизация тегов (с автоматическим подсчетом)
    $news->syncTagsWithCount([1, 2, 3]);

    // Добавление связанных новостей
    $news->relatedNews()->attach([5, 6, 7]);

    // Добавление изображений
    $news->images()->createMany([
        [
            'path' => 'news/gallery/1.jpg',
            'width' => 1920,
            'height' => 1080,
            'alt_text' => 'Скриншот 1',
        ],
        [
            'path' => 'news/gallery/2.jpg',
            'width' => 1920,
            'height' => 1080,
            'alt_text' => 'Скриншот 2',
        ],
    ]);
});
```

### Получение новостей для главной страницы

```php
$featuredNews = News::published()
    ->withFeaturedImage()
    ->with(['author', 'categories', 'tags'])
    ->recent()
    ->limit(5)
    ->get();
```

### Получение новостей категории

```php
$category = NewsCategory::where('slug', 'tehnologii')->firstOrFail();

$news = News::published()
    ->inCategory($category->id)
    ->with(['author', 'categories', 'tags'])
    ->recent()
    ->paginate(10);
```

### Получение популярных тегов

```php
$popularTags = NewsTag::popular(20)
    ->get()
    ->map(function ($tag) {
        return [
            'name' => $tag->name,
            'slug' => $tag->slug,
            'count' => $tag->usage_count,
            'url' => $tag->url,
        ];
    });
```

### Полнотекстовый поиск

```php
$searchQuery = 'Laravel 12';

$results = News::published()
    ->where(function ($query) use ($searchQuery) {
        $query->where('title', 'like', "%{$searchQuery}%")
              ->orWhere('content', 'like', "%{$searchQuery}%")
              ->orWhere('excerpt', 'like', "%{$searchQuery}%");
    })
    ->with(['author', 'categories', 'tags'])
    ->recent()
    ->paginate(10);
```

## Структура таблиц

Все таблицы созданы миграциями в `/database/migrations/`:

- `news_categories` - категории
- `news_tags` - теги
- `news` - новости
- `news_images` - изображения
- `category_news` - связь категорий и новостей
- `news_tag` - связь тегов и новостей
- `related_news` - связанные новости

## Best Practices

1. **Всегда используйте транзакции** при создании/обновлении новости с связями
2. **Используйте Eager Loading** для предотвращения N+1 проблем
3. **Используйте syncTagsWithCount()** вместо прямого sync() для тегов
4. **Не изменяйте slug** опубликованных новостей (для SEO)
5. **Используйте scopes** для повторяющихся запросов
6. **Проверяйте авторство** перед изменением новости
7. **Логируйте важные действия** (публикация, архивация)

## Права доступа

Рекомендуемая структура прав:

- **news.create** - создание новостей
- **news.edit.own** - редактирование своих новостей
- **news.edit.any** - редактирование любых новостей
- **news.delete.own** - удаление своих новостей
- **news.delete.any** - удаление любых новостей
- **news.publish** - публикация новостей
- **news.categories.manage** - управление категориями
- **news.tags.manage** - управление тегами

## Дополнительные возможности

### Планирование публикации

```php
// Запланировать публикацию на будущее
$news->update([
    'status' => News::STATUS_PUBLISHED,
    'published_at' => now()->addDays(3),
]);

// В запросах учитывается published_at
News::published(); // Только с published_at <= now()
```

### Статистика просмотров

```php
// Увеличение счетчика
$news->incrementViews();

// Популярные новости
$popular = News::published()
    ->popular()
    ->limit(10)
    ->get();
```

### SEO оптимизация

```php
// Установка SEO метаданных
$news->update([
    'seo_meta' => [
        'title' => 'SEO заголовок (60 символов)',
        'description' => 'SEO описание (160 символов)',
        'keywords' => 'ключевое, слово, список',
        'og_image' => 'path/to/og-image.jpg',
    ],
]);

// В ресурсе автоматически форматируется
```

## Заключение

Система новостей полностью готова к использованию и следует всем современным практикам Laravel 12. Все модели типизированы, документированы и протестированы на синтаксические ошибки.
