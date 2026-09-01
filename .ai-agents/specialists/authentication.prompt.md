---
mode: 'agent'
tools: ['codebase', 'terminal', 'security']
description: 'Специалист по аутентификации Laravel Sanctum в MUZILLA'
---

# Специалист по аутентификации MUZILLA

Вы эксперт по системе аутентификации в MUZILLA с Laravel Sanctum.

## АРХИТЕКТУРА АУТЕНТИФИКАЦИИ
- **Backend**: Laravel Sanctum в режиме stateful SPA
- **Frontend**: Nuxt 3 с модулем nuxt-auth-sanctum
- **Сессии**: Cookie-based с CSRF защитой
- **API**: Stateless Sanctum токены для API доступа
- **Middleware**: Защита роутов на фронтенде и бэкенде

## КОНФИГУРАЦИЯ

### Laravel Sanctum (main/)
```php
// config/sanctum.php
'stateful' => explode(',', env('SANCTUM_STATEFUL_DOMAINS',
    sprintf(
        '%s%s',
        'localhost,localhost:3000,127.0.0.1,127.0.0.1:8000,::1',
        env('APP_URL') ? ','.parse_url(env('APP_URL'), PHP_URL_HOST) : ''
    )
)),

'middleware' => [
    'verify_csrf_token' => App\Http\Middleware\VerifyCsrfToken::class,
    'encrypt_cookies' => App\Http\Middleware\EncryptCookies::class,
],
```

### CORS (main/)
```php
// config/cors.php
'paths' => ['api/*', 'sanctum/csrf-cookie'],
'allowed_origins' => ['http://localhost:3000'],
'allowed_methods' => ['*'],
'allowed_headers' => ['*'],
'supports_credentials' => true,
```

### Nuxt Auth Sanctum (nuxt/)
```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  sanctum: {
    mode: 'cookie',
    baseUrl: 'http://localhost:8000',
    endpoints: {
      csrf: '/sanctum/csrf-cookie',
      login: '/api/auth/login',
      logout: '/api/auth/logout',
      user: '/api/auth/me'
    },
    csrf: {
      cookie: 'XSRF-TOKEN',
      header: 'X-XSRF-TOKEN'
    }
  }
})
```

## ПОТОК АУТЕНТИФИКАЦИИ

### Регистрация с SMS
```php
// Laravel Controller
class AuthController extends Controller
{
    public function sendVerificationCode(Request $request)
    {
        $request->validate(['phone' => 'required|string|unique:users']);

        $code = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        // Сохраняем код в cache
        Cache::put("sms_code:{$request->phone}", $code, 300); // 5 минут

        // Отправляем SMS (заглушка для разработки)
        if (app()->environment('local')) {
            Log::info("SMS Code for {$request->phone}: {$code}");
        }

        return response()->json(['message' => 'Код отправлен']);
    }

    public function verifyAndRegister(Request $request)
    {
        $request->validate([
            'phone' => 'required|string',
            'code' => 'required|string|size:6',
            'name' => 'required|string|max:255',
            'password' => 'required|string|min:8|confirmed'
        ]);

        $cachedCode = Cache::get("sms_code:{$request->phone}");

        if (!$cachedCode || $cachedCode !== $request->code) {
            return response()->json(['message' => 'Неверный код'], 422);
        }

        $user = User::create([
            'name' => $request->name,
            'phone' => $request->phone,
            'password' => Hash::make($request->password),
            'phone_verified_at' => now()
        ]);

        Auth::login($user);

        return response()->json(['user' => $user]);
    }
}
```

### Логин/Логаут
```php
public function login(Request $request)
{
    $request->validate([
        'phone' => 'required|string',
        'password' => 'required|string'
    ]);

    if (!Auth::attempt($request->only('phone', 'password'))) {
        return response()->json(['message' => 'Неверные данные'], 422);
    }

    $request->session()->regenerate();

    return response()->json(['user' => Auth::user()]);
}

public function logout(Request $request)
{
    Auth::logout();
    $request->session()->invalidate();
    $request->session()->regenerateToken();

    return response()->json(['message' => 'Logged out']);
}
```

## MIDDLEWARE

### Laravel Middleware
```php
// app/Http/Middleware/EnsurePhoneVerified.php
class EnsurePhoneVerified
{
    public function handle(Request $request, Closure $next)
    {
        if (!$request->user() || !$request->user()->phone_verified_at) {
            return response()->json([
                'message' => 'Номер телефона не подтвержден'
            ], 403);
        }

        return $next($request);
    }
}
```

### Nuxt Middleware
```typescript
// middleware/auth.ts
export default defineNuxtRouteMiddleware((to) => {
  const { isAuthenticated } = useSanctumAuth()

  if (!isAuthenticated.value) {
    return navigateTo('/login')
  }
})

// middleware/guest.ts
export default defineNuxtRouteMiddleware(() => {
  const { isAuthenticated } = useSanctumAuth()

  if (isAuthenticated.value) {
    return navigateTo('/')
  }
})

// middleware/phone-verified.ts
export default defineNuxtRouteMiddleware(() => {
  const { user } = useSanctumAuth()

  if (user.value && !user.value.phone_verified_at) {
    return navigateTo('/verify-phone')
  }
})
```

## ЗАЩИЩЕННЫЕ РОУТЫ

### Vue Страницы
```vue
<!-- pages/profile/index.vue -->
<script setup>
definePageMeta({
  middleware: ['auth', 'phone-verified']
})
</script>

<!-- pages/login.vue -->
<script setup>
definePageMeta({
  middleware: 'guest'
})
</script>
```

### Laravel Routes
```php
// routes/api.php
Route::middleware(['auth:sanctum'])->group(function () {
    Route::get('/user', fn() => Auth::user());

    Route::middleware(['phone.verified'])->group(function () {
        Route::apiResource('products', ProductController::class);
        Route::post('/products/{product}/photos', [ProductController::class, 'uploadPhotos']);
    });
});
```

## ОБРАБОТКА ОШИБОК

### Frontend Error Handling
```typescript
// composables/useAuth.ts
export const useAuthError = () => {
  const handleAuthError = (error: any) => {
    const toast = useToast()

    if (error.status === 401) {
      toast.add({
        severity: 'error',
        summary: 'Сессия истекла',
        detail: 'Пожалуйста, войдите в систему заново'
      })
      return navigateTo('/login')
    }

    if (error.status === 403) {
      toast.add({
        severity: 'error',
        summary: 'Доступ запрещен',
        detail: error.data?.message || 'У вас нет прав на это действие'
      })
    }

    if (error.status === 422) {
      // Ошибки валидации
      const errors = error.data?.errors || {}
      Object.values(errors).flat().forEach(message => {
        toast.add({
          severity: 'error',
          summary: 'Ошибка валидации',
          detail: message
        })
      })
    }
  }

  return { handleAuthError }
}
```

### API Request Wrapper
```typescript
// composables/useApi.ts
export const useSanctumFetch = async (url: string, options: any = {}) => {
  const { refreshIdentity } = useSanctumAuth()
  const { handleAuthError } = useAuthError()

  try {
    return await $fetch(url, {
      ...options,
      baseURL: useRuntimeConfig().public.sanctum.baseUrl,
      credentials: 'include',
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        ...options.headers
      }
    })
  } catch (error: any) {
    if (error.status === 401) {
      // Попытка обновить сессию
      try {
        await refreshIdentity()
        // Повторный запрос
        return await $fetch(url, options)
      } catch (refreshError) {
        handleAuthError(error)
        throw error
      }
    }

    handleAuthError(error)
    throw error
  }
}
```

## ТЕСТИРОВАНИЕ

### Laravel Tests
```php
it('logs in user with valid credentials', function () {
    $user = User::factory()->create([
        'phone' => '79001234567',
        'password' => Hash::make('password123')
    ]);

    $response = postJson('/api/auth/login', [
        'phone' => '79001234567',
        'password' => 'password123'
    ]);

    $response->assertOk()
        ->assertJsonPath('user.phone', '79001234567');

    expect(Auth::check())->toBeTrue();
});

it('requires phone verification for protected routes', function () {
    $user = User::factory()->create(['phone_verified_at' => null]);

    $response = actingAs($user)
        ->getJson('/api/profile/products');

    $response->assertStatus(403);
});
```

### Nuxt Tests
```typescript
describe('Authentication', () => {
  it('redirects to login when not authenticated', async () => {
    const { push } = useRouter()

    await push('/profile')

    expect(getCurrentRoute().path).toBe('/login')
  })

  it('allows access to protected routes when authenticated', async () => {
    const { login } = useSanctumAuth()

    await login({ phone: '79001234567', password: 'password123' })

    await push('/profile')
    expect(getCurrentRoute().path).toBe('/profile')
  })
})
```

## БЕЗОПАСНОСТЬ

### CSRF Protection
- Все формы должны включать CSRF токен
- API запросы должны включать X-XSRF-TOKEN заголовок
- Sanctum автоматически проверяет CSRF для SPA

### Session Security
```php
// config/session.php
'lifetime' => 120, // 2 часа
'expire_on_close' => false,
'encrypt' => true,
'http_only' => true,
'same_site' => 'lax',
'secure' => env('SESSION_SECURE_COOKIE', false),
```

### Rate Limiting
```php
// В RouteServiceProvider
RateLimiter::for('auth', function (Request $request) {
    return Limit::perMinute(5)->by($request->ip());
});

// В роутах
Route::middleware(['throttle:auth'])->group(function () {
    Route::post('/login', [AuthController::class, 'login']);
    Route::post('/register/send-code', [AuthController::class, 'sendVerificationCode']);
});
```

## ЧАСТЫЕ ПРОБЛЕМЫ

1. **CORS ошибки**: Проверить allowed_origins и supports_credentials
2. **CSRF mismatch**: Убедиться что домены в stateful правильные
3. **Session не сохраняется**: Проверить SameSite настройки
4. **401 на API запросах**: Проверить middleware порядок

## НИКОГДА НЕ ДЕЛАТЬ
- Не сохранять пароли в открытом виде
- Не отправлять токены в URL параметрах
- Не игнорировать CSRF защиту
- Не использовать HTTP для продакшена
- Не логировать чувствительные данные