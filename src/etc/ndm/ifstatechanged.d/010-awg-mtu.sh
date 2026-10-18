#!/bin/sh
# Hook для автоматического восстановления MTU интерфейса AmneziaWG (Proxy42 / t2s42)

ENV_FILE="/opt/apps/kvas-awg/etc/conf/env.sh"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

PROXY_NAME="${KEENETIC_PROXY_NAME:-Proxy42}"

# Если вызван как хук ndm, проверяем контекст события
if [ "$1" = "hook" ]; then
    [ "$id" = "$PROXY_NAME" ] || exit 0
    case "${connected}-${link}-${up}" in
        *up*|*yes*) ;;
        *) exit 0 ;;
    esac
fi

AWG_CONF="/opt/etc/awg/awg.conf"
AWG_MTU=""
if [ -f "$AWG_CONF" ]; then
    AWG_MTU=$(awk -F '=' '
        tolower($1) ~ /^[[:space:]]*mtu[[:space:]]*$/ {
            gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' "$AWG_CONF" 2>/dev/null)
fi

case "$AWG_MTU" in
    ''|*[!0-9]*) AWG_MTU="${DEFAULT_PROXY_MTU:-${DEFAULT_AWG_MTU:-1376}}" ;;
esac

DEV="${system_name}"
if [ -z "$DEV" ]; then
    DEV=$(grep -E "^${PROXY_NAME}\|" /opt/etc/inface_equals 2>/dev/null | cut -d'|' -f2)
    [ -z "$DEV" ] && DEV=$(echo "$PROXY_NAME" | sed 's/Proxy/t2s/')
fi

# При прямом запуске даем до 5 секунд на появление интерфейса
if [ "$1" != "hook" ] && [ ! -d "/sys/class/net/$DEV" ]; then
    _i=0
    while [ "$_i" -lt 5 ]; do
        [ -d "/sys/class/net/$DEV" ] && break
        sleep 1
        _i=$((_i + 1))
    done
fi

if [ -n "$DEV" ] && [ -d "/sys/class/net/$DEV" ]; then
    CURRENT_MTU=$(cat "/sys/class/net/$DEV/mtu" 2>/dev/null)
    if [ "$CURRENT_MTU" != "$AWG_MTU" ]; then
        ip link set dev "$DEV" mtu "$AWG_MTU" 2>/dev/null
    fi

    # Зажим TCP MSS под MTU туннеля для предотвращения фрагментации TCP
    iptables -t mangle -C FORWARD -o "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -o "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null

    iptables -t mangle -C FORWARD -i "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -i "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
fi
