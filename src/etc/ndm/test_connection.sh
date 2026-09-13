#!/bin/sh

# Импортируем общие переменные
# shellcheck source=/dev/null
. /opt/apps/kvas-awg/etc/conf/env.sh

echo "Выполняется проверка проксирования через AmneziaWG 3.1 (wireproxy)..."

# Тест через SOCKS5 с удаленным DNS-резолвингом (socks5h)
IP_RESPONSE=$(curl -s --connect-timeout 7 -x "socks5h://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "https://ipinfo.io/ip" 2>/dev/null)

if [ -z "$IP_RESPONSE" ] || echo "$IP_RESPONSE" | grep -q -E "(Failed|Error|404|<html)"; then
    IP_RESPONSE=$(curl -s --connect-timeout 7 -x "socks5h://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "https://api.ipify.org" 2>/dev/null)
fi

if [ -n "$IP_RESPONSE" ] && ! echo "$IP_RESPONSE" | grep -q -E "(Failed|Error|404|<html)"; then
    echo -e "${GREEN}Тест успешно пройден!${NC}"
    echo -e "Ваш внешний IP через туннель AmneziaWG: ${BLUE}${IP_RESPONSE}${NC}"
    exit 0
else
    echo -e "${RED}Ошибка теста! Прокси-сервер не отвечает или туннель не установил соединение.${NC}"
    echo -e "${YELLOW}Рекомендации:${NC}"
    echo " 1. Проверьте статус службы: kvas-awg"
    echo " 2. Убедитесь, что параметры в ссылке (add) были верными."
    echo " 3. Проверьте журнал: cat /var/log/wireproxy.log"
    exit 1
fi
