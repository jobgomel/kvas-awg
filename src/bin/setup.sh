#!/bin/sh
set -e

APPS_DIR="/opt/apps/kvas-awg"
PRESERVED_ENV=0
TMP_ENV=""
WAS_RUNNING=0

while [ $# -gt 0 ]; do
    case "$1" in
        --preserved-env) PRESERVED_ENV="$2"; shift 2 ;;
        --env-backup)    TMP_ENV="$2"; shift 2 ;;
        --was-running)   WAS_RUNNING="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Если флаги не переданы, определяем состояние по факту
if [ -z "$TMP_ENV" ] && [ -f "${APPS_DIR}/etc/conf/env.sh" ]; then
    PRESERVED_ENV=1
fi

echo "Настройка компонентов kvas-awg..."

# 1. Синхронизация пользовательских настроек из бэкапа предыдущей установки
if [ "$PRESERVED_ENV" -eq 1 ] && [ -n "$TMP_ENV" ] && [ -f "$TMP_ENV" ]; then
    echo "Синхронизация пользовательских настроек (env.sh)..."
    TARGET_ENV="${APPS_DIR}/etc/conf/env.sh"
    if [ -f "$TARGET_ENV" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                \#*|"") continue ;;
                [A-Za-z_][A-Za-z0-9_]*=*)
                    key="${line%%=*}"
                    key=$(echo "$key" | tr -d " \t")
                    val="${line#*=}"
                    case "$key" in
                        RED|GREEN|YELLOW|BLUE|NC|KEENETIC_PROXY_NAME|KEENETIC_PROXY_DESC|PROXY_PROTO)
                            # Пропускаем системные константы (принудительно перезаписываются в const.sh)
                            continue
                            ;;
                    esac
                    if grep -q "^[[:space:]]*${key}=" "$TARGET_ENV"; then
                        esc_val=$(printf '%s\n' "$val" | sed -e 's/\\/\\\\/g' -e 's/[|&]/\\&/g')
                        sed -i "s|^[[:space:]]*${key}=.*|${key}=${esc_val}|" "$TARGET_ENV"
                    else
                        echo "${line}" >> "$TARGET_ENV"
                    fi
                    ;;
            esac
        done < "$TMP_ENV"
    else
        cp -f "$TMP_ENV" "$TARGET_ENV"
    fi
    rm -f "$TMP_ENV"
fi

# Очистка устаревших переменных цветов из env.sh (константы вынесены в const.sh)
TARGET_ENV="${APPS_DIR}/etc/conf/env.sh"
if [ -f "$TARGET_ENV" ]; then
    sed -i -E "/^[[:space:]]*(RED|GREEN|YELLOW|BLUE|NC)=/d" "$TARGET_ENV" 2>/dev/null || true
    if ! grep -q "const.sh" "$TARGET_ENV"; then
        TMP_FIX="/tmp/kvas_env_fix_$$.sh"
        {
            echo '#!/bin/sh'
            echo '[ -f /opt/apps/kvas-awg/etc/conf/const.sh ] && . /opt/apps/kvas-awg/etc/conf/const.sh'
            cat "$TARGET_ENV"
        } > "$TMP_FIX" && mv -f "$TMP_FIX" "$TARGET_ENV"
    fi
fi

# 2. Создание необходимых системных каталогов
mkdir -p /opt/bin \
         /opt/etc/awg \
         /opt/etc/ndm/ifstatechanged.d \
         "${APPS_DIR}/bin" \
         "${APPS_DIR}/etc/conf" \
         "${APPS_DIR}/etc/init.d" \
         "${APPS_DIR}/etc/ndm/ifstatechanged.d"

# 3. Назначение прав на исполнение скриптов пакета
chmod +x "${APPS_DIR}/bin/"*.sh 2>/dev/null || true
chmod +x "${APPS_DIR}/etc/init.d/"* 2>/dev/null || true
chmod +x "${APPS_DIR}/etc/ndm/"*.sh 2>/dev/null || true
chmod +x "${APPS_DIR}/etc/ndm/ifstatechanged.d/"*.sh 2>/dev/null || true

# 4. Создание системных симлинков
ln -sf "${APPS_DIR}/bin/manager.sh" /opt/bin/kvas-awg

INIT_SCRIPT="${APPS_DIR}/etc/init.d/S99awg"
if [ -f "$INIT_SCRIPT" ]; then
    mkdir -p /opt/etc/init.d
    chmod +x "$INIT_SCRIPT"
    ln -sf "$INIT_SCRIPT" /opt/etc/init.d/S99awg
fi

MTU_HOOK="${APPS_DIR}/etc/ndm/ifstatechanged.d/010-awg-mtu.sh"
if [ -f "$MTU_HOOK" ]; then
    chmod +x "$MTU_HOOK"
    ln -sf "$MTU_HOOK" /opt/etc/ndm/ifstatechanged.d/010-awg-mtu.sh
fi

# 5. Автоматическая калибровка профиля ресурсов при первичной установке
if [ "$PRESERVED_ENV" -eq 0 ]; then
    /opt/bin/kvas-awg mode auto
fi

# 6. Установка или обновление бинарника wireproxy-awg
if [ ! -f "${APPS_DIR}/bin/wireproxy" ]; then
    /opt/bin/kvas-awg install
else
    ln -sf "${APPS_DIR}/bin/wireproxy" /opt/bin/wireproxy
fi

# 7. Перезапуск службы при обновлении либо вывод статуса
if [ "$WAS_RUNNING" -eq 1 ] && [ -f "/opt/etc/init.d/S99awg" ]; then
    echo "Перезапуск службы wireproxy после обновления пакета..."
    /opt/etc/init.d/S99awg restart
else
    /opt/bin/kvas-awg
fi
