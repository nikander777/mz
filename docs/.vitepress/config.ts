import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'
import { processPages } from './processes'

// Документация MUZILLA — спецификация для согласования флоу с заказчиком и тестирования.
// Принцип: «одна тема — одна страница». Технические детали — в приложении «Техническая справка».
// Слева у процессов — статус-кружок готовности (🔴/🟠/🟡/🟢, легенда на лендинге).
// Нумерация — ТОЛЬКО у раздела «Процессы»: страница = верхний уровень (1, 2, 3…),
// а разделы внутри страницы (H2) авто-нумеруются темой как 1.1, 1.2… (см. processes.ts).
export default withMermaid(
  defineConfig({
    lang: 'ru-RU',
    title: 'MUZILLA — Документация',
    description:
      'Спецификация процессов MUZILLA: подробный флоу по каждому разделу для согласования и тестирования.',
    cleanUrls: true,
    lastUpdated: true,
    ignoreDeadLinks: true,

    themeConfig: {
      nav: [
        { text: 'О проекте', link: '/overview/' },
        { text: 'Процессы', link: '/overview/orders' },
        { text: 'Техсправка', link: '/processes/' },
      ],

      sidebar: [
        {
          text: 'О проекте',
          collapsed: false,
          items: [
            { text: 'О площадке', link: '/overview/' },
            { text: 'Справочник статусов', link: '/overview/statuses' },
            { text: 'К согласованию', link: '/overview/open-questions' },
            { text: 'Глоссарий', link: '/overview/glossary' },
          ],
        },
        {
          text: 'Процессы',
          collapsed: false,
          // Нумерация 1, 2, 3… и статус-кружок добавляются автоматически из processes.ts.
          items: processPages.map((p, i) => ({
            text: `${p.status} ${i + 1}. ${p.text}`,
            link: p.link,
          })),
        },
        {
          text: 'Техническая справка (приложение)',
          collapsed: true,
          items: [
            { text: 'Обзор', link: '/processes/' },
            { text: 'Жизненный цикл заказа', link: '/processes/order-lifecycle' },
            { text: 'Оформление (checkout)', link: '/processes/checkout' },
            { text: 'Платежи (Moneta)', link: '/processes/payments-moneta' },
            { text: 'Выплаты продавцам', link: '/business/seller-payouts-flow' },
            { text: 'Каталог и поиск', link: '/processes/catalog-search' },
            { text: 'Корзина и избранное', link: '/processes/cart-wishlist' },
            { text: 'Доставка', link: '/processes/delivery' },
            { text: 'Отзывы', link: '/processes/reviews' },
            { text: 'Продажа товара', link: '/processes/seller-listing' },
            { text: 'Регистрация и авторизация', link: '/processes/auth' },
            { text: 'Операции и команды', link: '/processes/operations' },
            { text: 'Матрица покрытия автотестами', link: '/testing/coverage-matrix' },
            { text: 'Клиентский тест-план (легаси)', link: '/testing/test-plan-client' },
            { text: 'Обзор проекта (стек, инфра)', link: '/project-overview' },
          ],
        },
      ],

      outline: { label: 'На странице', level: [2, 3] },
      docFooter: { prev: 'Предыдущая', next: 'Следующая' },
      darkModeSwitchLabel: 'Оформление',
      lightModeSwitchTitle: 'Светлая тема',
      darkModeSwitchTitle: 'Тёмная тема',
      sidebarMenuLabel: 'Меню',
      returnToTopLabel: 'Наверх',
      lastUpdatedText: 'Обновлено',

      search: {
        provider: 'local',
        options: {
          locales: {
            root: {
              translations: {
                button: {
                  buttonText: 'Поиск',
                  buttonAriaLabel: 'Поиск по документации',
                },
                modal: {
                  displayDetails: 'Показать подробности',
                  resetButtonTitle: 'Сбросить',
                  backButtonTitle: 'Назад',
                  noResultsText: 'Ничего не найдено',
                  footer: {
                    selectText: 'выбрать',
                    navigateText: 'навигация',
                    closeText: 'закрыть',
                  },
                },
              },
            },
          },
        },
      },
    },
  }),
)
