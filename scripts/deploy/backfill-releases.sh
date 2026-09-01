#!/bin/sh
# Авто-резюмирующий бэкфилл releases в Meili. Догоняет ~138k док, упавших на
# FST-ошибке (усиленный санитайзер их чинит). Устойчив к блипам Postgres:
# ждёт выхода из recovery и перескакивает crash-зону, если на ней нет прогресса.
cd /var/www/html
LOG=storage/logs/backfill-wrap.log
: > "$LOG"
last=0
prev=-1
for attempt in $(seq 1 60); do
  # ждём готовности Postgres (до ~10 мин)
  ok=0
  for w in $(seq 1 120); do
    if php artisan tinker --execute='try{ \DB::select("select 1"); echo "PGOK"; }catch(\Throwable $e){ echo "PGWAIT"; }' 2>/dev/null | grep -q PGOK; then ok=1; break; fi
    sleep 5
  done
  echo "[$(date -u +%H:%M:%S) attempt=$attempt from=$last pg_ready=$ok]" >> "$LOG"

  php artisan disco:meili-index releases --from="$last" --batch=2000 >> "$LOG" 2>&1

  if grep -q "=== releases:" "$LOG"; then
    echo "[$(date -u +%H:%M:%S) ALLDONE]" >> "$LOG"
    break
  fi

  newlast=$(grep -aoE 'last_id=[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+')
  [ -z "$newlast" ] && newlast="$last"

  if [ "$newlast" -le "$last" ] 2>/dev/null; then
    # прогресса нет — Postgres крашнулся на конкретной строке; перескочим зону
    last=$((last + 5000))
    echo "[$(date -u +%H:%M:%S) no-progress -> skip crash-zone to $last]" >> "$LOG"
  else
    last="$newlast"
  fi
done
echo "WRAPPER_DONE last=$last" >> "$LOG"
