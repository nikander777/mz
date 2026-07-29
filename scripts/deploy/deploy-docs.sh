#!/usr/bin/env bash
# Деплой статической документации MUZILLA (VitePress) на стейдж.
# URL после деплоя: http://dev.muzilla.ru:8088
#
# Изолированный compose-проект `muzilla-docs` — НЕ трогает основной стек
# и не страдает от его `--remove-orphans`. Обновление — просто перезапуск
# этого скрипта.
#
#   bash scripts/deploy/deploy-docs.sh
#
# Остановить/снести на сервере:
#   ssh root@dev.muzilla.ru 'cd /opt/muzilla-docs && docker compose -p muzilla-docs -f compose.docs.yml down'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
[[ -f "$SCRIPT_DIR/.env.deploy" ]] && source "$SCRIPT_DIR/.env.deploy"

KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
PORT="${SSH_PORT:-22}"
HOST="${SSH_USER:-root}@dev.muzilla.ru"
REMOTE="/opt/muzilla-docs"
SSH_E="ssh -i $KEY -o BatchMode=yes -p $PORT"

echo "[1/3] Сборка docs…"
npm run --prefix "$ROOT/docs" docs:build

echo "[2/3] Заливка на стейдж…"
$SSH_E "$HOST" "mkdir -p $REMOTE/dist"
rsync -az --delete -e "$SSH_E" "$ROOT/docs/.vitepress/dist/" "$HOST:$REMOTE/dist/"
rsync -az -e "$SSH_E" "$ROOT/compose.docs.yml" "$ROOT/docker/docs/nginx.conf" "$HOST:$REMOTE/"

echo "[3/3] Перезапуск контейнера…"
$SSH_E "$HOST" "cd $REMOTE && docker compose -p muzilla-docs -f compose.docs.yml up -d"

echo "Готово → http://dev.muzilla.ru:8088"
