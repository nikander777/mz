# MUZILLA — Документация

Централизованная документация проекта. Все разделы сгруппированы по тематикам.

## architecture/

- [`overview.md`](architecture/overview.md) — архитектурное видение и модули проекта

## api/

- [`admin-models-usage.md`](api/admin-models-usage.md) — AdminActivityLog, AuditTrail, SystemSetting, AdminNotification, Auditable trait
- [`api-cart.md`](api/api-cart.md) — REST API серверной корзины
- [`news-models.md`](api/news-models.md) — модуль новостей (News, NewsCategory, NewsTag, NewsImage)
- [`news-models-quickstart.md`](api/news-models-quickstart.md) — быстрый старт модуля новостей
- [`datatable-usage.md`](api/datatable-usage.md) — компонент DataTable с фильтрацией/сортировкой/экспортом

## deployment/

- [`demo-deployment.md`](deployment/demo-deployment.md) — разворачивание демо-окружения
- [`production-env.md`](deployment/production-env.md) — обязательные production переменные окружения
- [`production-reverb-config-example.php`](deployment/production-reverb-config-example.php) — шаблон `config/reverb.php`
- [`reverb.service.example`](deployment/reverb.service.example) — systemd-unit для Reverb

## testing/

- [`testing.md`](testing/testing.md) — quickstart по тестированию
- [`testing-comprehensive.md`](testing/testing-comprehensive.md) — полный тест-гайд (Pest, Vitest, Playwright)
- [`testing-system-summary.md`](testing/testing-system-summary.md) — отчёт покрытия и статистика

## frontend/

- [`admin-structure.md`](frontend/admin-structure.md) — структура админ-панели Nuxt (PrimeVue, layouts, страницы)
- [`admin-users-integration.md`](frontend/admin-users-integration.md) — интеграция управления пользователями

## database/

- [`polymorphic-favorites.md`](database/polymorphic-favorites.md) — миграция на полиморфные favorites
- [`create_sessions_table.sql`](database/create_sessions_table.sql) — SQL скрипт таблицы sessions

## business/

- `C2C.docx` — требования по C2C-функционалу
- `Описание структуры ЛК ООО М9.docx` — структура личного кабинета
