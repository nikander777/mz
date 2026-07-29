// Захват скриншотов dev.muzilla.ru в docs/public/screens для документации.
//
// Режимы:
//   node capture.mjs public   — публичные страницы (без входа)
//   node capture.mjs login    — открывает Chrome, ВЫ входите вручную (пароль ввожу не я);
//                               сессия сохраняется в профиле .chrome-profile
//   node capture.mjs auth     — авторизованные страницы (использует сохранённый профиль)
//
// Скриншоты не коммитятся автоматически — просмотрите и добавьте нужные.
import puppeteer from 'puppeteer-core'
import { mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = resolve(HERE, '../../docs/public/screens')
const PROFILE = resolve(HERE, '.chrome-profile')
const CHROME =
  process.env.CHROME_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const BASE = process.env.BASE_URL || 'https://dev.muzilla.ru'
const VIEWPORT = { width: 1440, height: 900, deviceScaleFactor: 2 }

const PUBLIC = [
  ['home', '/'],
  ['catalog', '/catalog'],
  ['disco-releases', '/disco/releases'],
  ['disco-artists', '/disco/artists'],
  ['disco-labels', '/disco/labels'],
  ['news', '/news'],
]

// Авторизованные экраны — заполняются по мере надобности (после `login`).
const AUTH = [
  ['buyer-orders', '/profile/orders'],
  ['buyer-profile', '/profile'],
  ['buyer-favorites', '/wishlist'],
  ['buyer-collection', '/profile/collection'],
  ['buyer-reviews', '/profile/reviews'],
  ['buyer-cart', '/cart'],
  ['buyer-checkout', '/checkout'],
  ['messages', '/messages'],
  ['seller-orders', '/seller/orders'],
  ['seller-products', '/seller/products'],
  ['seller-payout-setup', '/seller/payout-setup'],
  ['seller-statistics', '/seller/statistics'],
  ['seller-delivery', '/seller/delivery'],
  ['seller-pickup-points', '/seller/pickup-points'],
]

const mode = process.argv[2] || 'public'

async function shoot(page, name, path) {
  const url = BASE + path
  try {
    // domcontentloaded + settle — надёжнее для SPA (на некоторых страницах
    // networkidle не наступает из-за websocket/поллинга).
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 })
    await new Promise((r) => setTimeout(r, 3500))
    // Защита: если сессия истекла и нас перекинуло на вход — не сохраняем
    // (иначе перезатрём хороший снимок страницей логина).
    if (!path.includes('/login') && /\/login(\?|\/|$)/.test(page.url())) {
      console.log(`  ✗ ${name}  — редирект на вход (нужен повторный login), пропуск`)
      return
    }
    const file = resolve(OUT, `${name}.png`)
    await page.screenshot({ path: file, fullPage: false })
    console.log(`  ✓ ${name}  ${url}`)
  } catch (e) {
    console.log(`  ✗ ${name}  ${url}  — ${e.message.split('\n')[0]}`)
  }
}

async function main() {
  await mkdir(OUT, { recursive: true })

  if (mode === 'login') {
    console.log('Откроется Chrome. Войдите на dev.muzilla.ru вручную (пароль ввожу не я).')
    console.log('После входа окно закроется автоматически через 180 секунд или закройте его сами.')
    const browser = await puppeteer.launch({
      executablePath: CHROME,
      headless: false,
      userDataDir: PROFILE,
      defaultViewport: VIEWPORT,
      args: ['--no-sandbox', `--window-size=${VIEWPORT.width},${VIEWPORT.height}`],
    })
    const page = (await browser.pages())[0] || (await browser.newPage())
    await page.goto(BASE + '/login', { waitUntil: 'networkidle2', timeout: 45000 }).catch(() => {})
    await new Promise((r) => setTimeout(r, 180000))
    await browser.close()
    console.log('Сессия сохранена в профиле. Теперь: npm run capture:auth')
    return
  }

  const list = mode === 'auth' ? AUTH : PUBLIC
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    userDataDir: mode === 'auth' ? PROFILE : undefined,
    defaultViewport: VIEWPORT,
    args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars'],
  })
  const page = await browser.newPage()
  console.log(`Режим: ${mode}. Захват ${list.length} экранов → docs/public/screens/`)
  for (const [name, path] of list) await shoot(page, name, path)

  // Карточка товара (публичная): берём первую ссылку с каталога.
  if (mode === 'public') {
    try {
      await page.goto(BASE + '/catalog', { waitUntil: 'domcontentloaded', timeout: 45000 })
      await new Promise((r) => setTimeout(r, 3500))
      const href = await page.$$eval('a[href*="/catalog/product/"]', (els) =>
        els[0]?.getAttribute('href'),
      )
      if (href) {
        await page.goto(new URL(href, BASE).href, { waitUntil: 'domcontentloaded', timeout: 45000 })
        await new Promise((r) => setTimeout(r, 3500))
        await page.screenshot({ path: resolve(OUT, 'product.png'), fullPage: false })
        console.log(`  ✓ product  ${href}`)
      } else {
        console.log('  ✗ product — ссылка на товар не найдена')
      }
    } catch (e) {
      console.log(`  ✗ product — ${e.message.split('\n')[0]}`)
    }
  }

  await browser.close()
  console.log('Готово.')
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
