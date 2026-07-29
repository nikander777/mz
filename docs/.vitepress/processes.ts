// Единый источник порядка страниц-процессов.
// Номер страницы = индекс + 1. Используется в двух местах:
//   1) config.ts   — строит сайдбар раздела «Процессы» с нумерацией 1, 2, 3…
//   2) тема         — по этому же номеру авто-нумерует разделы (H2) внутри
//      страницы как «<номер страницы>.<номер раздела>» (1.1, 1.2…).
// Держим порядок здесь, чтобы сайдбар и внутренняя нумерация не расходились.

export type Status = '⚪' | '🔴' | '🟠' | '🟡' | '🟢'

export interface ProcessPage {
  /** Текст в сайдбаре (без номера и без кружка — они добавляются автоматически). */
  text: string
  /** Ссылка (cleanUrls). */
  link: string
  /** relativePath страницы — для сопоставления в теме. */
  path: string
  /** Статус готовности раздела. */
  status: Status
}

export const processPages: ProcessPage[] = [
  { text: 'Регистрация и роли', link: '/overview/auth', path: 'overview/auth.md', status: '🔴' },
  { text: 'Дискография', link: '/overview/discography', path: 'overview/discography.md', status: '🔴' },
  { text: 'Каталог / маркетплейс', link: '/overview/marketplace', path: 'overview/marketplace.md', status: '🔴' },
  { text: 'Карточка товара', link: '/overview/product', path: 'overview/product.md', status: '🔴' },
  { text: 'Работа с товарами', link: '/overview/seller-products', path: 'overview/seller-products.md', status: '🔴' },
  { text: 'Формат файла загрузки лотов', link: '/overview/product-import-format', path: 'overview/product-import-format.md', status: '🟢' },
  { text: 'Корзина и оформление', link: '/overview/cart-checkout', path: 'overview/cart-checkout.md', status: '🔴' },
  { text: 'Заказы: жизненный цикл', link: '/overview/orders', path: 'overview/orders.md', status: '🔴' },
  { text: 'Оплата', link: '/overview/payment', path: 'overview/payment.md', status: '🔴' },
  { text: 'Комиссии', link: '/overview/commissions', path: 'overview/commissions.md', status: '🔴' },
  { text: 'Доставка', link: '/overview/delivery', path: 'overview/delivery.md', status: '🔴' },
  { text: 'Выплаты продавцу', link: '/overview/payouts', path: 'overview/payouts.md', status: '🔴' },
  { text: 'Отзывы', link: '/overview/reviews', path: 'overview/reviews.md', status: '🔴' },
  { text: 'Сообщения', link: '/overview/messages', path: 'overview/messages.md', status: '🔴' },
  { text: 'Новости и блог', link: '/overview/news', path: 'overview/news.md', status: '🔴' },
  { text: 'Личный кабинет покупателя', link: '/overview/buyer-account', path: 'overview/buyer-account.md', status: '🔴' },
  { text: 'Кабинет продавца', link: '/overview/seller-account', path: 'overview/seller-account.md', status: '🔴' },
]

/** Сопоставление relativePath → номер страницы (1-based) для темы. */
export const processNumberByPath: Record<string, number> = Object.fromEntries(
  processPages.map((p, i) => [p.path, i + 1]),
)

/** Сопоставление relativePath → статус готовности (кружок) для ноутиса на странице. */
export const statusByPath: Record<string, Status> = Object.fromEntries(
  processPages.map((p) => [p.path, p.status]),
)
