#!/bin/bash
#
# Закрыть порты данных VM-3 для всех, кроме VM-1 и VM-2.
#
# ЗАЧЕМ. Docker публикует порты в обход ufw: его DNAT срабатывает раньше цепочки
# INPUT, где живут правила ufw. Поэтому Postgres (5432), Meilisearch (7700),
# MinIO (9000/9001) и legacy MySQL (3306) были открыты всему интернету — в логе
# Postgres ~240 попыток подбора пароля в сутки (10.09.2026), 29.09.2026 все
# четыре порта отвечали с произвольного адреса. Единственное место, где docker
# даёт фильтровать такой трафик, — цепочка DOCKER-USER.
#
# Фильтр — только на внешнем интерфейсе: DOCKER-USER видит и трафик между
# контейнерами на мосту (br_netfilter), и правило без -i отрезало бы, например,
# pgbackups от Postgres.
#
# Идемпотентен: пересоздаёт свою цепочку MZ-DATA-GUARD при каждом запуске.
#
# УСТАНОВКА на VM-3 (92.255.105.112):
#   cp scripts/deploy/vm3-data-guard.sh /usr/local/sbin/ && chmod +x /usr/local/sbin/vm3-data-guard.sh
#   юнит /etc/systemd/system/vm3-data-guard.service (Type=oneshot, After/Requires=docker.service,
#   ExecStart=/usr/local/sbin/vm3-data-guard.sh, RemainAfterExit=yes, WantedBy=multi-user.target)
#   systemctl daemon-reload && systemctl enable --now vm3-data-guard.service
#
# Доступ к базам с ноутбука — только через туннель:
#   ssh -N -L 15432:localhost:5432 root@92.255.105.112

set -euo pipefail

EXT_IF=${EXT_IF:-enp1s0f1}
ALLOWED="90.156.211.143 85.193.81.19" # VM-1, VM-2
PORTS="5432,5433,7700,7701,9000,9001,3306"
CHAIN=MZ-DATA-GUARD

iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"
for ip in $ALLOWED; do
    iptables -A "$CHAIN" -s "$ip" -j RETURN
done
iptables -A "$CHAIN" -j DROP

# Прыжок в цепочку — первым правилом DOCKER-USER, ровно один раз.
while iptables -D DOCKER-USER -i "$EXT_IF" -p tcp -m multiport --dports "$PORTS" -j "$CHAIN" 2>/dev/null; do :; done
iptables -I DOCKER-USER 1 -i "$EXT_IF" -p tcp -m multiport --dports "$PORTS" -j "$CHAIN"

echo "vm3-data-guard: порты $PORTS на $EXT_IF открыты только для $ALLOWED"
