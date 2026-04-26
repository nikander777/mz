// Тестирование Nuxt аутентификации
console.log('🧪 Тестирование Nuxt аутентификации...')

// Имитируем браузерный запрос с cookies
const puppeteer = require('puppeteer')

async function testNuxtAuth() {
  let browser
  try {
    console.log('🚀 Запуск браузера...')
    browser = await puppeteer.launch({
      headless: false,
      devtools: true
    })

    const page = await browser.newPage()

    // Включаем логи консоли
    page.on('console', msg => console.log('🖥️  BROWSER:', msg.text()))
    page.on('pageerror', error => console.log('❌ PAGE ERROR:', error.message))

    console.log('1️⃣ Переходим на страницу логина...')
    await page.goto('http://localhost:3000/login', { waitUntil: 'networkidle0' })

    console.log('2️⃣ Заполняем форму логина...')
    await page.type('input[name="email"]', 'nikander@me.com')
    await page.type('input[name="password"]', 'password')

    console.log('3️⃣ Отправляем форму...')
    await page.click('button[type="submit"]')

    // Ожидаем редиректа
    await page.waitForNavigation({ waitUntil: 'networkidle0' })

    console.log('4️⃣ Текущий URL:', page.url())

    console.log('5️⃣ Переходим на страницу сообщений...')
    await page.goto('http://localhost:3000/messages', { waitUntil: 'networkidle0' })

    console.log('6️⃣ URL после перехода на messages:', page.url())

    console.log('7️⃣ Обновляем страницу...')
    await page.reload({ waitUntil: 'networkidle0' })

    console.log('8️⃣ URL после обновления:', page.url())

    // Проверяем cookies
    const cookies = await page.cookies()
    console.log('🍪 Cookies:', cookies.map(c => `${c.name}=${c.value.substring(0, 20)}...`))

    // Ждем 5 секунд чтобы можно было посмотреть результат
    console.log('⏰ Ждем 5 секунд для просмотра...')
    await new Promise(resolve => setTimeout(resolve, 5000))

  } catch (error) {
    console.error('❌ Ошибка теста:', error)
  } finally {
    if (browser) {
      await browser.close()
    }
  }
}

// Запускаем тест
testNuxtAuth().then(() => {
  console.log('✅ Тест завершен')
  process.exit(0)
}).catch(error => {
  console.error('❌ Ошибка:', error)
  process.exit(1)
})