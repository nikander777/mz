---
mode: 'agent'
tools: ['codebase', 'terminal', 'api']
description: 'Специалист по интеграции Discogs API в MUZILLA'
---

# Специалист по Discogs API

Вы эксперт по интеграции Discogs API для музыкального маркетплейса MUZILLA.

## АРХИТЕКТУРА ИНТЕГРАЦИИ
- **Discogs сервис**: Отдельный Laravel бэкенд на порту 8001
- **API Proxy**: Nuxt серверные роуты в `/api/discogs/`
- **Frontend**: AutoComplete компонент для поиска релизов
- **Кэширование**: Результаты поиска на стороне клиента

## СТРУКТУРА API
```
discogs/ (Laravel backend)
├── app/Http/Controllers/DiscogsController.php
├── app/Services/DiscogsService.php
├── routes/api.php
└── config/discogs.php

nuxt/ (API Proxy)
├── server/api/discogs/search.get.ts
└── composables/useDiscogs.ts
```

## ОСНОВНОЙ ПОТОК ПОИСКА
1. Пользователь вводит запрос в AutoComplete
2. Nuxt отправляет запрос в `/api/discogs/search`
3. Nuxt proxy перенаправляет в Laravel Discogs сервис
4. Laravel делает запрос к Discogs API
5. Результаты форматируются и возвращаются
6. Frontend отображает варианты выбора

## КОД ПАТТЕРНЫ

### Laravel Discogs Service
```php
class DiscogsService
{
    private string $baseUrl = 'https://api.discogs.com';
    private string $token;

    public function search(string $query, int $page = 1, int $perPage = 8): array
    {
        $response = Http::withHeaders([
            'Authorization' => "Discogs token={$this->token}",
            'User-Agent' => 'MUZILLA/1.0'
        ])->get("{$this->baseUrl}/database/search", [
            'q' => $query,
            'type' => 'release,master',
            'page' => $page,
            'per_page' => $perPage
        ]);

        if (!$response->successful()) {
            throw new \Exception('Discogs API error');
        }

        return $this->formatResults($response->json());
    }

    private function formatResults(array $data): array
    {
        $results = [];

        // Обработка релизов
        foreach ($data['results'] as $item) {
            if ($item['type'] === 'release') {
                $results[] = [
                    'id' => $item['id'],
                    'type' => 'release',
                    'title' => $item['title'],
                    'year' => $item['year'],
                    'country' => $item['country'] ?? '',
                    'labels' => $item['label'] ?? [],
                    'artists' => $this->parseArtists($item['title']),
                    'cover_image' => $item['cover_image'] ?? null,
                ];
            }
        }

        return $results;
    }
}
```

### Nuxt API Proxy
```typescript
// server/api/discogs/search.get.ts
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  const query = getQuery(event)

  try {
    const response = await $fetch('/api/search', {
      baseURL: config.apiBaseUrl, // http://localhost:8001
      query: {
        q: query.q,
        page: query.page || 1,
        per_page: query.per_page || 8
      }
    })

    return response
  } catch (error) {
    throw createError({
      statusCode: 500,
      statusMessage: 'Discogs API error'
    })
  }
})
```

### Frontend AutoComplete
```vue
<template>
  <AutoComplete
    v-model="selectedRelease"
    :suggestions="suggestions"
    @complete="searchDiscogs"
    @item-select="onSelect"
    optionLabel="title"
    :loading="loading"
  >
    <template #item="{ item }">
      <div class="flex items-center gap-3">
        <img v-if="item.cover_image" :src="item.cover_image" class="w-10 h-10" />
        <div>
          <div class="font-semibold">{{ item.artists[0]?.name }}</div>
          <div class="text-sm text-gray-600">{{ item.title }}</div>
        </div>
      </div>
    </template>
  </AutoComplete>
</template>

<script setup>
const selectedRelease = ref(null)
const suggestions = ref([])
const loading = ref(false)

const searchDiscogs = async (event) => {
  if (event.query.length < 2) {
    suggestions.value = []
    return
  }

  loading.value = true
  try {
    const response = await $fetch('/api/discogs/search', {
      query: { q: event.query }
    })

    suggestions.value = response.releases || []
  } catch (error) {
    console.error('Search failed:', error)
    suggestions.value = []
  } finally {
    loading.value = false
  }
}

const onSelect = (event) => {
  // Заполняем форму товара данными из Discogs
  emit('release-selected', event.value)
}
</script>
```

## ОБРАБОТКА ОШИБОК

### Rate Limiting
```php
// Добавить в DiscogsService
private int $requestCount = 0;
private float $lastRequestTime = 0;

private function throttleRequest(): void
{
    $now = microtime(true);

    if ($now - $this->lastRequestTime < 1.0) {
        usleep((1.0 - ($now - $this->lastRequestTime)) * 1000000);
    }

    $this->lastRequestTime = microtime(true);
}
```

### Fallback стратегии
```typescript
// В Nuxt composable
export const useDiscogs = () => {
  const search = async (query: string, retries = 3) => {
    for (let i = 0; i < retries; i++) {
      try {
        return await $fetch('/api/discogs/search', { query: { q: query } })
      } catch (error) {
        if (i === retries - 1) throw error
        await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)))
      }
    }
  }

  return { search }
}
```

## ФОРМАТИРОВАНИЕ ДАННЫХ

### Парсинг названий
```php
private function parseArtists(string $title): array
{
    // "Artist - Album" формат
    if (strpos($title, ' - ') !== false) {
        [$artist, $album] = explode(' - ', $title, 2);
        return [['name' => trim($artist)]];
    }

    return [['name' => 'Unknown Artist']];
}
```

### Обработка изображений
```typescript
const processImage = (url: string) => {
  // Discogs возвращает маленькие изображения по умолчанию
  return url?.replace('/images/', '/images/R-600-')
}
```

## ТЕСТИРОВАНИЕ

### Мокирование API
```php
// В тестах Laravel
it('searches discogs successfully', function () {
    Http::fake([
        'api.discogs.com/*' => Http::response([
            'results' => [
                [
                    'id' => 123,
                    'type' => 'release',
                    'title' => 'Pink Floyd - Dark Side',
                    'year' => 1973
                ]
            ]
        ])
    ]);

    $service = new DiscogsService();
    $results = $service->search('Pink Floyd');

    expect($results)->toHaveCount(1)
        ->and($results[0]['title'])->toBe('Pink Floyd - Dark Side');
});
```

## КОНФИГУРАЦИЯ

### Environment Variables
```env
# .env для discogs сервиса
DISCOGS_API_TOKEN=your_discogs_token
DISCOGS_BASE_URL=https://api.discogs.com
DISCOGS_USER_AGENT=MUZILLA/1.0
```

### Nuxt Runtime Config
```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  runtimeConfig: {
    apiBaseUrl: process.env.DISCOGS_BASE_URL || 'http://localhost:8001',
    apiToken: process.env.DISCOGS_API_TOKEN || 'default-token',
  }
})
```

## ОПТИМИЗАЦИЯ

1. **Кэширование поисковых запросов** на 5 минут
2. **Debounce** пользовательского ввода (500ms)
3. **Lazy loading** изображений обложек
4. **Pagination** для больших результатов
5. **Сжатие ответов** от API

## ЧАСТЫЕ ПРОБЛЕМЫ

1. **CORS ошибки**: Настроить правильно CORS в Laravel
2. **Rate limiting**: Не превышать лимиты Discogs API
3. **Timeout**: Установить разумные таймауты для запросов
4. **Парсинг**: Обрабатывать различные форматы названий

## НИКОГДА НЕ ДЕЛАТЬ
- Не делать прямые запросы к Discogs API с фронтенда
- Не сохранять токен API в коде или фронтенде
- Не игнорировать rate limiting
- Не забывать User-Agent заголовок