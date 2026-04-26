#!/usr/bin/env node

async function testCollectionsAPI() {
  console.log('🧪 Тестирование исправленного API коллекций через Nuxt сервер');
  console.log('');

  const NUXT_URL = 'http://localhost:3000';

  // Test data
  const testRelease = {
    release_id: 999,
    title: 'Test Album Fixed',
    artist: 'Test Artist Fixed',
    year: 2023,
    format: 'Vinyl',
    condition: 'mint',
    notes: 'Test notes after fixes'
  };

  try {
    console.log('🔐 Предварительная проверка аутентификации...');
    console.log('⚠️  ВНИМАНИЕ: Для корректной работы необходимо быть авторизованным в браузере');
    console.log('');

    console.log('1️⃣ Тестирование проверки статуса в коллекции...');
    const checkResponse = await fetch(`${NUXT_URL}/api/profile/collections/check`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ release_id: testRelease.release_id })
    });

    console.log('Статус ответа:', checkResponse.status);
    if (checkResponse.status === 401) {
      console.log('❌ Ошибка аутентификации. Убедитесь что вы авторизованы в браузере');
    } else if (checkResponse.status === 200) {
      console.log('✅ Аутентификация прошла успешно');
      const checkResult = await checkResponse.json();
      console.log('Ответ:', JSON.stringify(checkResult, null, 2));
    } else {
      const checkResult = await checkResponse.text();
      console.log('Ответ:', checkResult);
    }
    console.log('');

    if (checkResponse.status === 200) {
      console.log('2️⃣ Тестирование переключения в коллекции...');
      const toggleResponse = await fetch(`${NUXT_URL}/api/profile/collections/toggle`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(testRelease)
      });

      console.log('Статус ответа:', toggleResponse.status);
      if (toggleResponse.status === 200) {
        const toggleResult = await toggleResponse.json();
        console.log('Ответ:', JSON.stringify(toggleResult, null, 2));
      } else {
        const toggleResult = await toggleResponse.text();
        console.log('Ответ:', toggleResult);
      }
      console.log('');

      console.log('3️⃣ Тестирование добавления в коллекцию...');
      const addResponse = await fetch(`${NUXT_URL}/api/profile/collections`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ ...testRelease, release_id: testRelease.release_id + 1 })
      });

      console.log('Статус ответа:', addResponse.status);
      if (addResponse.status === 200 || addResponse.status === 201) {
        const addResult = await addResponse.json();
        console.log('Ответ:', JSON.stringify(addResult, null, 2));
      } else {
        const addResult = await addResponse.text();
        console.log('Ответ:', addResult);
      }
      console.log('');

      console.log('4️⃣ Тестирование получения коллекции...');
      const getResponse = await fetch(`${NUXT_URL}/api/profile/collections`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        }
      });

      console.log('Статус ответа:', getResponse.status);
      if (getResponse.status === 200) {
        const getResult = await getResponse.json();
        console.log('Количество элементов в коллекции:', getResult.data?.length || 0);
        if (getResult.data?.length > 0) {
          console.log('Первый элемент:', JSON.stringify(getResult.data[0], null, 2));
        }
      } else {
        const getResult = await getResponse.text();
        console.log('Ответ:', getResult);
      }
    }

  } catch (error) {
    console.error('❌ Ошибка при тестировании:', error.message);
  }

  console.log('');
  console.log('✅ Тест завершен');
  console.log('');
  console.log('📝 Примечания:');
  console.log('- Для работы API требуется авторизация через браузер');
  console.log('- CSRF токены передаются автоматически при наличии cookies');
  console.log('- Все ошибки 401 указывают на проблемы аутентификации');
}

testCollectionsAPI();