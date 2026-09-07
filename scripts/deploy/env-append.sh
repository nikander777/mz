#!/usr/bin/env bash
# env-append.sh — безопасно дописать KEY=VALUE в .env.
#
# Зачем: `echo "KEY=VALUE" >> .env` на файле без перевода строки в конце
# приклеивает новую переменную к последней строке. Прецедент VM-2:
# PAYMENTS_PLATFORM_PHONE прилип к DISCOGS_API_URL, и обе переменные перестали
# читаться. Скрипт проверяет `tail -c1`, добивает перевод строки, не дублирует
# уже существующие ключи и не печатает значения в stdout.
#
# Использование:
#   bash scripts/deploy/env-append.sh KEY=VALUE [KEY2=VALUE2 ...]
#   grep '^MONETA_' /откуда/.env | bash scripts/deploy/env-append.sh --stdin
#   bash scripts/deploy/env-append.sh --check            # только проверить
#   bash scripts/deploy/env-append.sh --ensure-newline   # только добить \n
#
# Опции:
#   --file <path>      файл (по умолчанию ./.env)
#   --stdin            читать строки KEY=VALUE из stdin (пустые и # пропускаются)
#   --replace          если ключ уже есть — заменить значение (по умолчанию
#                      пропуск с предупреждением); перед заменой делается
#                      бэкап .env.bak-append-<timestamp>
#   --check            ничего не писать: код 0, если файл в порядке; 1, если
#                      нет перевода строки в конце или найдены склеенные строки
#   --ensure-newline   добавить перевод строки в конец, если его нет, и выйти
#                      (pre-flight в deploy.sh / prod-deploy.yml)
#   --example <path>   эталон ключей для поиска склеек (по умолчанию
#                      .env.prod.example рядом с файлом, если есть)
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

ENV_FILE=".env"
EXAMPLE_FILE=""
MODE="append"
FROM_STDIN=0
REPLACE=0
ENTRIES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)           ENV_FILE="$2"; shift 2 ;;
        --example)        EXAMPLE_FILE="$2"; shift 2 ;;
        --stdin)          FROM_STDIN=1; shift ;;
        --replace)        REPLACE=1; shift ;;
        --check)          MODE="check"; shift ;;
        --ensure-newline) MODE="ensure-newline"; shift ;;
        -h|--help)        sed -n '2,29p' "$0"; exit 0 ;;
        --*)              error "Неизвестная опция: $1"; exit 2 ;;
        *)                ENTRIES+=("$1"); shift ;;
    esac
done

[[ -f "$ENV_FILE" ]] || { error "Нет файла $ENV_FILE"; exit 2; }
if [[ -z "$EXAMPLE_FILE" && -f "$(dirname "$ENV_FILE")/.env.prod.example" ]]; then
    EXAMPLE_FILE="$(dirname "$ENV_FILE")/.env.prod.example"
fi

# Файл непустой и последний байт — не перевод строки.
lacks_trailing_newline() {
    [[ -s "$ENV_FILE" && -n "$(tail -c1 "$ENV_FILE")" ]]
}

ensure_trailing_newline() {
    if lacks_trailing_newline; then
        printf '\n' >> "$ENV_FILE"
        warn "$ENV_FILE был без перевода строки в конце — добавлен"
    fi
}

# Склейка: известный ключ встречается не в начале строки и не как хвост
# другого ключа (перед ним не [A-Z0-9_]), например
# DISCOGS_API_URL=https://muzilla.ruPAYMENTS_PLATFORM_PHONE=+7...
# Список ключей берём из эталона; без него проверка пропускается.
scan_glued_lines() {
    local found=0 key lines
    [[ -n "$EXAMPLE_FILE" && -f "$EXAMPLE_FILE" ]] || return 0
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        # grep -q читает файл напрямую: пайп с ранним закрытием под pipefail
        # давал бы ложный «чисто».
        if grep -qE "^[^#].*[^A-Z0-9_]${key}=" "$ENV_FILE"; then
            lines="$(grep -nE "^[^#].*[^A-Z0-9_]${key}=" "$ENV_FILE" | cut -d: -f1 | paste -sd, -)"
            warn "похоже на склейку: ${key}= внутри строки ${lines} файла $ENV_FILE"
            found=1
        fi
    done < <(grep -oE '^[A-Z][A-Z0-9_]*=' "$EXAMPLE_FILE" | tr -d '=' | sort -u)
    return $found
}

case "$MODE" in
    check)
        rc=0
        if lacks_trailing_newline; then
            warn "$ENV_FILE без перевода строки в конце: следующий 'echo >> .env' склеит переменные"
            rc=1
        fi
        scan_glued_lines || rc=1
        [[ $rc -eq 0 ]] && info "$ENV_FILE в порядке"
        exit $rc
        ;;
    ensure-newline)
        ensure_trailing_newline
        scan_glued_lines || warn "разберите склеенные строки руками: nano $ENV_FILE"
        exit 0
        ;;
esac

# ---- append ----
if [[ $FROM_STDIN -eq 1 ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        ENTRIES+=("$line")
    done
fi

[[ ${#ENTRIES[@]} -gt 0 ]] || { error "Нечего дописывать: передай KEY=VALUE или --stdin"; exit 2; }

for entry in "${ENTRIES[@]}"; do
    key="${entry%%=*}"
    if [[ "$entry" != *=* || ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        error "Ожидаю KEY=VALUE, получил строку с ключом '${key}'"
        exit 2
    fi
done

ensure_trailing_newline

backup_done=0
added=0
replaced=0
skipped=0
for entry in "${ENTRIES[@]}"; do
    key="${entry%%=*}"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        if [[ $REPLACE -eq 1 ]]; then
            if [[ $backup_done -eq 0 ]]; then
                cp -p "$ENV_FILE" "$ENV_FILE.bak-append-$(date +%Y%m%d-%H%M%S)"
                backup_done=1
            fi
            tmp="$(mktemp "$(dirname "$ENV_FILE")/.env-append.XXXXXX")"
            # ENVIRON — чтобы значение с / & \ не трактовалось как паттерн.
            KEY="$key" LINE="$entry" awk '
                BEGIN { k = ENVIRON["KEY"] "="; l = ENVIRON["LINE"] }
                !done && index($0, k) == 1 { print l; done = 1; next }
                { print }
            ' "$ENV_FILE" > "$tmp"
            cat "$tmp" > "$ENV_FILE"   # сохраняем inode и права файла
            rm -f "$tmp"
            replaced=$((replaced + 1))
            info "заменён $key"
        else
            skipped=$((skipped + 1))
            warn "пропущен $key — уже есть в $ENV_FILE (нужна замена — добавь --replace)"
        fi
    else
        printf '%s\n' "$entry" >> "$ENV_FILE"
        added=$((added + 1))
        info "добавлен $key"
    fi
done

info "готово: добавлено $added, заменено $replaced, пропущено $skipped → $ENV_FILE"
scan_glued_lines || warn "в файле остались склеенные строки — разберите руками: nano $ENV_FILE"
