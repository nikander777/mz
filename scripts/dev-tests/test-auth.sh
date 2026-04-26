#!/bin/bash

echo "🧪 Тестирование аутентификации через API"
echo ""

# Base URL
BASE_URL="http://localhost:8000"
COOKIE_JAR="/tmp/cookies.txt"

# Test credentials
EMAIL="nikander@me.com"
PASSWORD="password"

echo "1️⃣ Получение CSRF cookie..."
curl -s -c "$COOKIE_JAR" \
  -X GET \
  "$BASE_URL/sanctum/csrf-cookie" \
  -H "Accept: application/json" \
  -H "Origin: http://localhost:3000" \
  -H "Referer: http://localhost:3000"
echo "✅ CSRF cookie получен"

# Extract XSRF token
XSRF_TOKEN=$(grep "XSRF-TOKEN" "$COOKIE_JAR" | awk '{print $7}')
echo "🔑 XSRF Token: ${XSRF_TOKEN:0:20}..."

echo ""
echo "2️⃣ Попытка входа..."
LOGIN_RESPONSE=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -X POST \
  "$BASE_URL/api/auth/login" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -H "Referer: http://localhost:3000" \
  -H "X-XSRF-TOKEN: $XSRF_TOKEN" \
  -d "{\"login\": \"$EMAIL\", \"password\": \"$PASSWORD\"}")

echo "Response: $LOGIN_RESPONSE"

echo ""
echo "3️⃣ Проверка авторизации - запрос /api/auth/me..."
ME_RESPONSE=$(curl -s -b "$COOKIE_JAR" \
  -X GET \
  "$BASE_URL/api/auth/me" \
  -H "Accept: application/json" \
  -H "Origin: http://localhost:3000" \
  -H "Referer: http://localhost:3000" \
  -H "X-XSRF-TOKEN: $XSRF_TOKEN")

echo "Response: $ME_RESPONSE"

echo ""
echo "4️⃣ Cookies в файле:"
cat "$COOKIE_JAR"

echo ""
echo "✅ Тест завершен"