# MUZILLA — Документация

Централизованная документация проекта. Все разделы сгруппированы по тематикам.

## 🚀 Документация как сайт (VitePress)

Документация собирается в статический сайт с навигацией, поиском и Mermaid-схемами. Три раздела по цепочке: **Обзор проекта** (флоу простым языком) → **Техническая документация** (методы, хранение, команды) → **Тестирование** (проверки).

```bash
cd docs
npm install
npm run docs:dev      # локально http://localhost:5173
npm run docs:build    # статическая сборка в docs/.vitepress/dist
```

Точки входа: [`index.md`](index.md) (лендинг) · [`overview/`](overview/) · [`processes/`](processes/) · [`testing/`](testing/).

> Источник — Markdown в этой папке, версионируется вместе с кодом. Ниже — плоский индекс файлов.

---

## Обзор проекта

- [`project-overview.md`](project-overview.md) — обзор проекта: стек, мощности серверов, интеграции, масштаб (памятка для созвонов и онбординга)

## overview/ (Обзор проекта — флоу простым языком)

- [`index.md`](overview/index.md) — о площадке + список разделов
- Постранично: `auth`, `discography`, `marketplace`, `product`, `cart-checkout`, `orders`, `buyer-account`, `seller-account`, `messages`, `reviews`, `news`

## processes/ (Техническая документация — «что где вызывается»)

- [`index.md`](processes/index.md) — карта процессов + приоритеты
- [`order-lifecycle.md`](processes/order-lifecycle.md) — жизненный цикл заказа (P0)
- [`checkout.md`](processes/checkout.md) — оформление заказа + корзина (P0)
- [`payments-moneta.md`](processes/payments-moneta.md) — платежи Moneta (P0)
- `auth`, `catalog-search`, `cart-wishlist`, `delivery`, `reviews`, `seller-listing`, `operations`

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

- [`index.md`](testing/index.md) — стратегия тестирования и приоритеты (P0/P1/P2)
- [`coverage-matrix.md`](testing/coverage-matrix.md) — матрица покрытия: процесс × приоритет × автотесты × пробел
- [`test-plan-client.md`](testing/test-plan-client.md) — клиентский тест-план (функциональные блоки, стенд, тестовые аккаунты, формат бага)
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

- [`seller-payouts-flow.md`](business/seller-payouts-flow.md) — флоу продавца: регистрация, витрина, подключение выплат (ФЛ/ЮЛ/ИП), договор с НКО, выплаты по заказам и сценарии восстановления
- `C2C.docx` — требования по C2C-функционалу
- `Описание структуры ЛК ООО М9.docx` — структура личного кабинета
