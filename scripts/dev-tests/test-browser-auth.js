// Симуляция браузерного тестирования аутентификации
const puppeteer = require('puppeteer');

async function testAuthFlow() {
  const browser = await puppeteer.launch({
    headless: false,
    devtools: false,
    args: ['--no-sandbox']
  });

  try {
    const page = await browser.newPage();

    // Включаем логи консоли
    page.on('console', msg => {
      if (msg.type() === 'log' || msg.type() === 'error') {
        console.log(`🖥️  [${msg.type().toUpperCase()}]`, msg.text());
      }
    });

    // Перехватываем сетевые запросы для отладки
    page.on('response', response => {
      const url = response.url();
      if (url.includes('api/auth') || url.includes('sanctum') || url.includes('login')) {
        console.log(`🌐 ${response.status()} ${response.request().method()} ${url}`);
      }
    });

    console.log('1️⃣ Переходим на страницу логина...');
    await page.goto('http://localhost:3000/login', { waitUntil: 'networkidle0' });

    console.log('2️⃣ Заполняем форму логина...');
    await page.type('#email', 'nikander@me.com');
    await page.type('#password', 'password');

    console.log('3️⃣ Отправляем форму...');
    await page.click('button[type="submit"]');

    // Ждем перехода
    await page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 10000 });
    console.log('4️⃣ URL после логина:', page.url());

    // Проверяем что мы не на странице логина
    if (page.url().includes('/login')) {
      console.log('❌ Остались на странице логина - ошибка аутентификации');
      return false;
    }

    console.log('5️⃣ Переходим на страницу сообщений...');
    await page.goto('http://localhost:3000/messages', { waitUntil: 'networkidle0' });
    console.log('6️⃣ URL страницы сообщений:', page.url());

    // Проверяем что мы попали на страницу сообщений
    if (page.url().includes('/login')) {
      console.log('❌ Перенаправило на логин - middleware не работает');
      return false;
    }

    console.log('7️⃣ Обновляем страницу сообщений...');
    await page.reload({ waitUntil: 'networkidle0' });
    console.log('8️⃣ URL после обновления:', page.url());

    // Главная проверка - остались ли мы на странице сообщений после обновления
    if (page.url().includes('/login')) {
      console.log('❌ ПРОБЛЕМА: После обновления перенаправило на логин!');
      return false;
    } else {
      console.log('✅ УСПЕХ: После обновления остались на странице сообщений!');
      return true;
    }

  } catch (error) {
    console.error('❌ Ошибка теста:', error.message);
    return false;
  } finally {
    await browser.close();
  }
}

// Проверяем что puppeteer установлен
try {
  require.resolve('puppeteer');
} catch (e) {
  console.log('⚠️  Puppeteer не установлен. Установите: npm install puppeteer');
  process.exit(1);
}

testAuthFlow().then(success => {
  if (success) {
    console.log('\n✅ Тест пройден: Аутентификация сохраняется при обновлении страницы');
  } else {
    console.log('\n❌ Тест не пройден: Проблема с сохранением аутентификации');
  }
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('\n❌ Критическая ошибка:', error);
  process.exit(1);
});