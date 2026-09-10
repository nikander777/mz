#!/bin/bash
#
# Сторож Postgres на VM-3: диагностика падений + автоматическое снятие залипания.
#
# ЗАЧЕМ. 10.09.2026 дискография и карточки товаров лежали 3 ч 24 мин, и никто
# этого не заметил. Само падение кластера длится 2-3 секунды — в многочасовой
# простой его превращает то, что бывает ПОСЛЕ: часть бэкендов остаётся ждать
# завершения ввода-вывода буфера (wait_event = BufferIo), флаг которого осиротел
# от процесса, убитого аварией. Ожидание непрерываемо: pg_terminate_backend
# возвращает true, а бэкенд висит дальше — проверено, 20 минут после «killed».
# Восемь таких бэкендов = весь пул php-fpm дискографии, и сервис умирает целиком.
#
# Снять залипание можно ТОЛЬКО переинициализацией разделяемой памяти, то есть
# рестартом Postgres. Пул php-fpm на VM-1 освобождается при этом сам: рестарт
# рвёт клиентские соединения, и зависший recv возвращает ошибку.
#
# Порог 180 с выбран с запасом: штатное ожидание BufferIo измеряется
# миллисекундами, три минуты — заведомо залипание, а не нагрузка.
# Пауза 15 минут между рестартами не даёт сторожу устроить петлю.
#
# УСТАНОВКА на VM-3 (92.255.105.112):
#   scp scripts/deploy/pg-panic-watch.sh root@VM3:/usr/local/bin/
#   chmod +x /usr/local/bin/pg-panic-watch.sh
#   systemd-юниты pg-panic-watch.service + .timer (OnUnitActiveSec=1min),
#   systemctl enable --now pg-panic-watch.timer
# Лог: /var/log/pg-panic-watch.log
#
# Требует на стороне Postgres: ALTER SYSTEM SET log_parameter_max_length_on_error = -1
# — без него в логе PANIC нет значений bind-параметров, то есть неизвестен
# id релиза, а по нему находится битая страница.

LOG=/var/log/pg-panic-watch.log
COOLDOWN_FILE=/var/lib/pg-panic-watch.last-restart
SEEN_FILE=/var/lib/pg-panic-watch.last-seen
COOLDOWN=900
STUCK_AGE=180

log() { echo "$(date -Is) $*" >> "$LOG"; }

psql_q() { docker exec muzilla-postgres-1 psql -U muzilla -d postgres -Atc "$1" 2>/dev/null; }

# 1. Контекст падений. Благодаря log_parameter_max_length_on_error = -1 сюда
#    попадают значения bind-параметров, то есть id релиза — именно так
#    выяснилось, что падают РАЗНЫЕ релизы (4384591 на странице 525307,
#    2092171 на 141514) с одними и теми же числами в PANIC. Значит битой
#    страницы кучи нет, ломается что-то общее для любого обновления.
#
#    Окно чтения шире периода запуска, иначе падение на стыке минут потеряется.
#    Расплата — та же запись видна дважды, поэтому отсекаем уже сохранённое
#    по метке времени последней записанной строки.
seen=$(cat "$SEEN_FILE" 2>/dev/null || echo '0000-00-00 00:00:00')
fresh=$(docker logs --since 2m muzilla-postgres-1 2>&1 | grep -A6 'PANIC:' \
        | awk -v seen="$seen" '$0 ~ /^[0-9][0-9][0-9][0-9]-/ { ts = $1 " " $2; keep = (ts > seen) } keep')

if [ -n "$fresh" ]; then
    echo "$fresh" >> "$LOG"
    echo "$fresh" | awk '$0 ~ /^[0-9][0-9][0-9][0-9]-/ { ts = $1 " " $2 } END { print ts }' > "$SEEN_FILE"
fi

# 2. Залипшие бэкенды по всему кластеру, старше порога.
stuck=$(psql_q "select count(*) from pg_stat_activity where state = 'active' and wait_event = 'BufferIo' and query_start < now() - interval '$STUCK_AGE seconds';")

if [ -z "$stuck" ]; then
    log 'СТОРОЖ: psql недоступен'
    exit 0
fi

[ "$stuck" -eq 0 ] && exit 0

log "СТОРОЖ: залипших на BufferIo дольше ${STUCK_AGE}с: $stuck"
psql_q "select pid || ' | ' || coalesce(datname,'-') || ' | ' || (now()-query_start)::text || ' | ' || left(query, 120) from pg_stat_activity where state = 'active' and wait_event = 'BufferIo';" >> "$LOG"

# 3. Пауза между рестартами.
now=$(date +%s)
last=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)

if [ $((now - last)) -lt $COOLDOWN ]; then
    log "СТОРОЖ: рестарт был $((now - last))с назад, жду (пауза ${COOLDOWN}с)"
    exit 0
fi

log 'СТОРОЖ: перезапускаю muzilla-postgres-1'
echo "$now" > "$COOLDOWN_FILE"
docker restart -t 30 muzilla-postgres-1 >> "$LOG" 2>&1
sleep 15

after=$(psql_q "select count(*) from pg_stat_activity where state = 'active' and wait_event = 'BufferIo';")
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://muzilla.ru/catalog/product/deti-deti-gruppa-deti-570948 2>/dev/null)
log "СТОРОЖ: после рестарта залипших: ${after:-?}, карточка товара отдаёт ${code:-нет ответа}"
