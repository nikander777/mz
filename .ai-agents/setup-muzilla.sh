#!/bin/bash

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🎵 Настройка среды разработки MUZILLA${NC}"
echo "==========================================="

# Проверка зависимостей
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 не установлен${NC}"
        echo "Пожалуйста, установите $1 и запустите скрипт снова"
        exit 1
    else
        echo -e "${GREEN}✓ $1 найден${NC}"
    fi
}

echo -e "${YELLOW}Проверка зависимостей...${NC}"
check_dependency "php"
check_dependency "composer"
check_dependency "node"
check_dependency "npm"
check_dependency "git"

# Версии
echo -e "\n${YELLOW}Версии:${NC}"
php -v | head -n 1
node -v
npm -v

# Backend Setup - Main
echo -e "\n${BLUE}📦 Настройка Laravel Main${NC}"
echo "--------------------------------"
cd main

if [ ! -d "vendor" ]; then
    echo "Установка composer пакетов..."
    composer install --no-interaction
fi

if [ ! -f .env ]; then
    echo "Создание .env файла..."
    cp .env.example .env
    php artisan key:generate

    echo -e "${YELLOW}Настройте параметры в .env файле при необходимости${NC}"
fi

if [ ! -f "database/database.sqlite" ]; then
    echo "Создание SQLite базы данных..."
    touch database/database.sqlite
fi

echo "Запуск миграций..."
php artisan migrate --force

echo "Настройка storage..."
php artisan storage:link

cd ..

# Backend Setup - Discogs
echo -e "\n${BLUE}📀 Настройка Laravel Discogs${NC}"
echo "----------------------------------"
cd discogs

if [ ! -d "vendor" ]; then
    echo "Установка composer пакетов..."
    composer install --no-interaction
fi

if [ ! -f .env ]; then
    echo "Создание .env файла..."
    cp .env.example .env
    php artisan key:generate

    echo -e "${YELLOW}Добавьте DISCOGS_API_TOKEN в .env файл${NC}"
fi

cd ..

# Frontend Setup
echo -e "\n${BLUE}💚 Настройка Nuxt Frontend${NC}"
echo "--------------------------------"
cd nuxt

if [ ! -d "node_modules" ]; then
    echo "Установка npm пакетов..."
    npm install
fi

if [ ! -f .env ]; then
    echo "Создание .env файла..."
    echo "NUXT_PUBLIC_API_BASE=http://localhost:8000" > .env
    echo "NUXT_PUBLIC_DISCOGS_BASE=http://localhost:8001" >> .env
fi

cd ..

# Git Hooks Setup
echo -e "\n${BLUE}🔧 Настройка Git Hooks${NC}"
echo "------------------------"
if [ ! -d ".git" ]; then
    git init
fi

git config core.hooksPath .hooks
chmod +x .hooks/*
echo -e "${GREEN}✓ Git hooks настроены${NC}"

# Создание алиасов
echo -e "\n${BLUE}🎹 Создание алиасов MUZILLA${NC}"
echo "------------------------------"

# Определяем путь к проекту
PROJECT_PATH=$(pwd)

# Проверяем какой shell используется
if [ -f ~/.zshrc ]; then
    SHELL_RC=~/.zshrc
elif [ -f ~/.bashrc ]; then
    SHELL_RC=~/.bashrc
else
    SHELL_RC=~/.bash_profile
fi

# Добавляем алиасы если их еще нет
if ! grep -q "# MUZILLA Aliases" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << EOL

# MUZILLA Aliases
alias mz-main="cd $PROJECT_PATH/main && composer run dev"
alias mz-discogs="cd $PROJECT_PATH/discogs && php artisan serve --port=8001"
alias mz-nuxt="cd $PROJECT_PATH/nuxt && npm run dev"
alias mz-test-main="cd $PROJECT_PATH/main && composer test"
alias mz-test-nuxt="cd $PROJECT_PATH/nuxt && npm run test"
alias mz-check="cd $PROJECT_PATH && echo 'Checking main...' && cd main && composer check && cd ../nuxt && echo 'Checking nuxt...' && npm run check"
alias mz-fix="cd $PROJECT_PATH && echo 'Fixing main...' && cd main && composer fix && cd ../nuxt && echo 'Fixing nuxt...' && npm run fix"
EOL

    echo -e "${GREEN}✓ Алиасы добавлены в $SHELL_RC${NC}"
    echo -e "${YELLOW}Перезагрузите терминал или выполните: source $SHELL_RC${NC}"
else
    echo -e "${GREEN}✓ Алиасы уже настроены${NC}"
fi

# Финальная проверка
echo -e "\n${BLUE}✅ Проверка настройки${NC}"
echo "----------------------"

# Проверка Laravel main
if [ -f "main/artisan" ]; then
    echo -e "${GREEN}✓ Laravel main настроен${NC}"
else
    echo -e "${RED}❌ Проблема с Laravel main${NC}"
fi

# Проверка Laravel discogs
if [ -f "discogs/artisan" ]; then
    echo -e "${GREEN}✓ Laravel discogs настроен${NC}"
else
    echo -e "${RED}❌ Проблема с Laravel discogs${NC}"
fi

# Проверка Nuxt
if [ -f "nuxt/nuxt.config.ts" ]; then
    echo -e "${GREEN}✓ Nuxt настроен${NC}"
else
    echo -e "${RED}❌ Проблема с Nuxt${NC}"
fi

# Инструкции
echo -e "\n${GREEN}🎉 MUZILLA среда разработки готова!${NC}"
echo "========================================"
echo -e "${BLUE}Команды для запуска:${NC}"
echo "  Main Backend:     mz-main      (http://localhost:8000)"
echo "  Discogs Backend:  mz-discogs   (http://localhost:8001)"
echo "  Nuxt Frontend:    mz-nuxt      (http://localhost:3000)"
echo ""
echo -e "${BLUE}Команды для тестирования:${NC}"
echo "  Main Backend:  mz-test-main"
echo "  Nuxt Frontend: mz-test-nuxt"
echo "  Все проверки:  mz-check"
echo "  Исправления:   mz-fix"
echo ""
echo -e "${BLUE}Важно:${NC}"
echo "  - Настройте DISCOGS_API_TOKEN в discogs/.env"
echo "  - Сервисы уже запущены, не перезапускайте их!"
echo "  - Main: http://localhost:8000"
echo "  - Discogs: http://localhost:8001"
echo "  - Reverb: http://localhost:8080"
echo "  - Nuxt: http://localhost:3000"
echo ""
echo -e "${GREEN}Happy coding! 🎵${NC}"