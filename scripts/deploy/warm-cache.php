<?php

// Прогрев прод-кеша дискографии. Скармливается в `php artisan tinker` внутри
// контейнера discogs (stdin), чтобы не упереться в HTTP/FPM-таймаут (504).
//
// Греет:
//   1. App-cache (Redis) — discogs:overview + filter_options:{releases,artists,masters}:all
//      (TTL 600с, ровно те ключи, что дёргает Nuxt SSR).
//   2. Postgres shared_buffers — прогоняет сами листинги (paginate count(*) не кешируется
//      в Redis, но после первого прохода страницы таблиц/индексов лежат в buffer cache).

use Illuminate\Support\Facades\Cache;
use Illuminate\Http\Request;
use App\Http\Controllers\StatsController;
use App\Http\Controllers\ReleaseController;
use App\Http\Controllers\ArtistController;

echo '=== WARM START ===' . PHP_EOL;
echo 'cache.default=' . config('cache.default') . PHP_EOL;

try {
    Cache::store()->put('warm_ping', 1, 10);
    echo 'redis_ok=' . Cache::store()->get('warm_ping') . PHP_EOL;
} catch (\Throwable $e) {
    echo 'CACHE_ERR=' . $e->getMessage() . PHP_EOL;
}

$run = function (string $label, callable $fn): void {
    $t = microtime(true);
    try {
        $fn();
        echo $label . '=' . round((microtime(true) - $t) * 1000) . 'ms' . PHP_EOL;
    } catch (\Throwable $e) {
        echo $label . '_ERR=' . $e->getMessage() . PHP_EOL;
    }
};

$stats = new StatsController();
$releases = new ReleaseController();
$artists = new ArtistController();

// --- App-cache (Redis) ---
$run('overview', fn () => $stats->overview());
$run('filter_releases_all', fn () => $stats->filterOptions(new Request(['entity_type' => 'releases', 'type' => 'all'])));
$run('filter_masters_all', fn () => $stats->filterOptions(new Request(['entity_type' => 'masters', 'type' => 'all'])));
$run('filter_artists_all', fn () => $stats->filterOptions(new Request(['entity_type' => 'artists', 'type' => 'all'])));

// --- Postgres buffer cache: дефолтные листинги (страница 1, как из Nuxt) ---
$run('list_releases_default', fn () => $releases->index(new Request(['page_size' => 20, 'sort' => 'popularity'])));
$run('list_releases_title', fn () => $releases->index(new Request(['page_size' => 20, 'sort' => 'title'])));
$run('list_artists_name', fn () => $artists->index(new Request(['page_size' => 20, 'sort' => 'name'])));
$run('list_artists_popularity', fn () => $artists->index(new Request(['page_size' => 20, 'sort' => 'popularity'])));

echo '=== WARM DONE ===' . PHP_EOL;
