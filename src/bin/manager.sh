#!/bin/sh

# Изолированные базовые пути приложения
APP_NAME="kvas-awg"
APP_BASE="/opt/apps/${APP_NAME}"
ENV_CONFIG="${APP_BASE}/etc/conf/env.sh"

# Импортируем глобальные переменные проекта
if [ -f "$ENV_CONFIG" ]; then
    . "$ENV_CONFIG"
else
    echo "Критическая ошибка: Файл конфигурации среды $ENV_CONFIG не найден!"
    exit 1
fi

# Пути к компонентам приложения
BIN_PATH="${APP_BASE}/bin/wireproxy"
TEMPLATE_INIT="${APP_BASE}/etc/init.d/S99awg"
CHECK_SPACE_SCRIPT="${APP_BASE}/etc/ndm/check_space.sh"
TEST_SCRIPT="${APP_BASE}/etc/ndm/test_connection.sh"

# Глобальные системные пути Entware
FINAL_CONFIG_DIR="/opt/etc/awg"
FINAL_CONFIG_PATH="${FINAL_CONFIG_DIR}/awg.conf"
SYSTEM_INIT_PATH="/opt/etc/init.d/S99awg"
PIDFILE="/var/run/wireproxy.pid"
LOGFILE="/var/log/wireproxy.log"

show_status() {
    echo "=== Менеджер Kvas-AmneziaWG (wireproxy-awg) ==="
    if [ -f "$BIN_PATH" ]; then
        VERSION=$($BIN_PATH --help 2>&1 | head -n 1)
        [ -z "$VERSION" ] && VERSION="Установлен"
        echo -e "Статус: ${GREEN}Установлен${NC} ($VERSION)"
    else
        echo -e "Статус: ${RED}Не установлен${NC}"
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo -e "Служба: ${GREEN}Запущена${NC} (PID: $(cat "$PIDFILE"))"
    else
        echo -e "Служба: ${RED}Остановлена${NC}"
    fi

    if [ -f "$FINAL_CONFIG_PATH" ]; then
        echo -e "Конфигурация: ${GREEN}Активна${NC} ($FINAL_CONFIG_PATH)"
        ENDPOINT=$(grep -i '^[[:space:]]*Endpoint' "$FINAL_CONFIG_PATH" | head -n 1 | awk -F'=' '{print $2}' | tr -d ' 
')
        [ -n "$ENDPOINT" ] && echo " -> Сервер Endpoint: $ENDPOINT"
        AWG_PARAMS=$(grep -i -E '^[[:space:]]*(HeaderProtectionKey|ContentPaddingAddition|RandomTrailers|Jc|S1|H1)' "$FINAL_CONFIG_PATH" | tr -d ' ' | tr '\n' ', ' | sed 's/,$//')
        [ -n "$AWG_PARAMS" ] && echo " -> Параметры обфускации: $AWG_PARAMS"
    else
        echo -e "Конфигурация: ${YELLOW}Ожидает импорта ссылки или файла (add)${NC}"
    fi
    echo "----------------------------------------"
    echo "Использование:"
    echo "  ${APP_NAME} install          - Скачать/обновить бинарный файл wireproxy-awg"
    echo "  ${APP_NAME} uninstall        - Полное удаление пакета и интеграции"
    echo -e "  ${APP_NAME} add ${BLUE}"link"${NC}       - Импорт 'vpn://...', 'awg://...', Base64 или файла"
    echo "  ${APP_NAME} test             - Экспресс-тест проксирования туннеля"
    echo "  ${APP_NAME} log              - Просмотр журнала работы демона"
    echo "  ${APP_NAME} start | stop | restart"
}

run_test() {
    if [ -f "$TEST_SCRIPT" ]; then
        "$TEST_SCRIPT"
    else
        return 1
    fi
}

install_wireproxy() {
    if [ -f "$CHECK_SPACE_SCRIPT" ]; then
        if ! "$CHECK_SPACE_SCRIPT"; then
            exit 1
        fi
    fi

    echo "Определение архитектуры процессора..."
    ARCH=$(uname -m)
    case "$ARCH" in
        *aarch64*|*arm64*)            BINARY_ARCH="arm64" ;;
        *armv7*|*armv6*|*arm*)        BINARY_ARCH="arm" ;;
        *mipsle*|*mipsel*)            BINARY_ARCH="mipsle" ;;
        *mips*)
            # Подавляющее большинство MIPS Keenetic (MT7621, MT7628) - mipsel (little-endian)
            BINARY_ARCH="mipsle"
            ;;
        *x86_64*|*amd64*)             BINARY_ARCH="amd64" ;;
        *i?86*|*x86*)                 BINARY_ARCH="386" ;;
        *)                            BINARY_ARCH="" ;;
    esac

    if [ -z "$BINARY_ARCH" ]; then
        echo -e "${RED}Ошибка: Не удалось определить архитектуру устройства ($ARCH).${NC}"
        exit 1
    fi

    echo "Запрос актуальной версии wireproxy-awg с GitHub..."
    LATEST_VERSION=$(curl -sI https://github.com/artem-russkikh/wireproxy-awg/releases/latest 2>/dev/null | grep -i 'location:' | sed -E 's/.*\/tag\/([^[:space:]\r\n]+).*/\1/')

    if [ -z "$LATEST_VERSION" ] || echo "$LATEST_VERSION" | grep -q "{" ; then
        echo -e "${YELLOW}Предупреждение: Не удалось определить последний тег, используем стабильный v1.0.18${NC}"
        LATEST_VERSION="v1.0.18"
    fi

    TMP_DIR="/tmp/wireproxy_install_$$"
    TMP_ARCHIVE="${TMP_DIR}/wireproxy.tar.gz"
    mkdir -p "$TMP_DIR"

    DOWNLOAD_URL="https://github.com/artem-russkikh/wireproxy-awg/releases/download/${LATEST_VERSION}/wireproxy_linux_${BINARY_ARCH}.tar.gz"

    echo -e "Скачиваем ${BLUE}wireproxy-awg ${LATEST_VERSION}${NC} для ${YELLOW}${BINARY_ARCH}${NC}..."
    if ! curl -L -f -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
        echo -e "${RED}Ошибка: Не удалось скачать архив с GitHub (${DOWNLOAD_URL}).${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "Распаковка архива..."
    if ! tar -xzf "$TMP_ARCHIVE" -C "$TMP_DIR"; then
        echo -e "${RED}Ошибка: Не удалось распаковать архив.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    TMP_BIN=$(find "$TMP_DIR" -type f -name "wireproxy" | head -n 1)

    if [ -z "$TMP_BIN" ] || [ ! -f "$TMP_BIN" ]; then
        echo -e "${RED}Ошибка: Бинарный файл wireproxy не найден внутри скачанного архива.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    chmod +x "$TMP_BIN"

    # Проверка совместимости бинарника с текущей системой
    if "$TMP_BIN" --help >/dev/null 2>&1 || "$TMP_BIN" -h >/dev/null 2>&1; then
        echo -e "${GREEN}Бинарный файл wireproxy успешно проверен на совместимость.${NC}"
    else
        echo -e "${RED}Ошибка: Скачанный файл wireproxy не может быть запущен на этом ядре/архитектуре.${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Проверка работы текущей службы
    WAS_RUNNING=0
    if [ -f "$SYSTEM_INIT_PATH" ] && [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        WAS_RUNNING=1
        echo "Остановка текущей службы для обновления..."
        "$SYSTEM_INIT_PATH" stop
    fi

    # Установка бинарника в изолированную директорию приложения
    mkdir -p "${APP_BASE}/bin"
    mv "$TMP_BIN" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    ln -sf "$BIN_PATH" /opt/bin/wireproxy
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}Бинарный файл wireproxy-awg успешно установлен!${NC}"

    if [ "$WAS_RUNNING" -eq 1 ]; then
        echo "Перезапуск службы..."
        "$SYSTEM_INIT_PATH" start
        sleep 2
        run_test
    else
        echo ""
        echo -e "${YELLOW}Для настройки подключения выполните:${NC}"
        echo -e "  ${BLUE}kvas-awg add "vpn://W0ludGVyZmF..."${NC}"
        echo -e "  или импортируйте файл: ${BLUE}kvas-awg add /opt/etc/awg/client.conf${NC}"
        echo -e "${RED}Важно:${NC} Ссылку обязательно оборачивать в двойные кавычки ${GREEN}""${NC}!"
    fi
}

add_config() {
    INPUT="$1"

    # 1. Если аргумент не передан или передан '-' — читаем через read / stdin
    # Это полностью обходит 512-байтный лимит интерактивной строки ash
    if [ -z "$INPUT" ] || [ "$INPUT" = "-" ]; then
        echo -e "${YELLOW}Вставьте ссылку (vpn://...), Base64 или путь к файлу и нажмите Enter:${NC}"
        read -r INPUT
    fi

    if [ -z "$INPUT" ]; then
        echo -e "${RED}Ошибка: Конфигурация или ссылка не указана!${NC}"
        exit 1
    fi

    TMP_DECODED="${APP_BASE}/etc/conf/decoded.tmp"
    rm -f "$TMP_DECODED"

    echo "Обработка конфигурации..."

    RAW_CONTENT=""

    # 2. Если передан путь к локальному файлу
    if [ -f "$INPUT" ]; then
        echo "Чтение из файла $INPUT..."
        RAW_CONTENT=$(cat "$INPUT")
    # 3. Если передана HTTP/HTTPS ссылка
    elif echo "$INPUT" | grep -q -E '^https?://'; then
        echo "Загрузка по веб-ссылке $INPUT..."
        RAW_CONTENT=$(curl -sL "$INPUT")
    else
        RAW_CONTENT="$INPUT"
    fi

    # 4. Проверяем, сырой ли это INI-файл или Base64/vpn://
    if echo "$RAW_CONTENT" | grep -qi "\[Interface\]" && echo "$RAW_CONTENT" | grep -qi "\[Peer\]"; then
        echo "Использован готовый текст конфигурации."
        echo "$RAW_CONTENT" > "$TMP_DECODED"
    else
        # Очистка строки от пробелов, табуляций и переносов
        CLEAN_STR=$(echo "$RAW_CONTENT" | tr -d ' \t\r\n')

        # Удаление префиксов схем
        case "$CLEAN_STR" in
            vpn://*|awg://*|amnezia://*|wireguard://*)
                B64_PAYLOAD="${CLEAN_STR#*://}"
                ;;
            *)
                B64_PAYLOAD="$CLEAN_STR"
                ;;
        esac

        # 1. Нормализация URL-Safe Base64 в стандартный Base64:
        # заменяем '_' на '/' и '-' на '+'
        B64_PAYLOAD=$(echo "$B64_PAYLOAD" | tr '_-' '/+')

        # 2. Дополняем паддинг '=' до кратности 4, если генератор его опустил
        MOD=$((${#B64_PAYLOAD} % 4))
        if [ "$MOD" -eq 2 ]; then
            B64_PAYLOAD="${B64_PAYLOAD}=="
        elif [ "$MOD" -eq 3 ]; then
            B64_PAYLOAD="${B64_PAYLOAD}="
        fi

        # Декодирование Base64
        DECODED=$(echo "$B64_PAYLOAD" | base64 -d 2>/dev/null || true)

        if [ -n "$DECODED" ]; then
            echo "$DECODED" > "$TMP_DECODED"
        fi
    fi

	  # 5. Валидация структуры
    if [ ! -s "$TMP_DECODED" ] || ! grep -qi "\[Interface\]" "$TMP_DECODED"; then
        # Детектор сжатого JSON-контейнера Amnezia (zlib / qCompress)
        # Такие ссылки всегда начинаются с 'AA...' из-за 4-байтового заголовка длины
        if echo "$B64_PAYLOAD" | grep -qE '^AA' || echo "$RAW_CONTENT" | grep -qE '^(vpn|awg)://AA'; then
            echo ""
            echo -e "${RED}══════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}ОШИБКА: Обнаружен закрытый формат ссылки Amnezia VPN!${NC}"
            echo -e "${RED}══════════════════════════════════════════════════════════════════════${NC}"
            echo -e "Данная ссылка представляет собой сжатый Base64URL/zlib-архив"
            echo -e "с внутренней JSON-структурой клиента Amnezia."
            echo -e "Декодирование этого архива встроенными средствами BusyBox невозможно."
            echo ""
            echo -e "${YELLOW}Как получить рабочий файл:${NC}"
            echo -e " 1. Откройте приложение Amnezia VPN на ПК или смартфоне."
            echo -e " 2. Перейдите в 'Настройки' -> выберите сервер -> 'AmneziaWG'."
            echo -e " 3. Нажмите 'Поделиться' -> выберите ${GREEN}'Файл конфигурации'${NC} (.conf)"
            echo -e "    (для WireGuard / сторонних клиентов), а не 'Ссылка'."
            echo -e " 4. Сохраните файл на роутер и выполните импорт:"
            echo -e "    ${BLUE}kvas-awg add /opt/etc/awg/client.conf${NC}"
            echo -e "${RED}══════════════════════════════════════════════════════════════════════${NC}"
            echo ""
            rm -f "$TMP_DECODED"
            exit 1
        fi

        echo -e "${RED}Ошибка: Не удалось извлечь блок [Interface]. Проверьте правильность ссылки.${NC}"
        rm -f "$TMP_DECODED"
        exit 1
    fi

    if ! grep -qi "\[Peer\]" "$TMP_DECODED"; then
        echo -e "${RED}Ошибка: Блок [Peer] отсутствует или был обрезан терминалом!${NC}"
        echo -e "${YELLOW}Рекомендация: Запустите 'kvas-awg add' без аргументов и вставьте ссылку по запросу, либо передайте файл: 'kvas-awg add /path/to/file'.${NC}"
        rm -f "$TMP_DECODED"
        exit 1
    fi

    echo -e "${GREEN}Конфигурация AmneziaWG 3.1 успешно распознана!${NC}"

    mkdir -p "$FINAL_CONFIG_DIR"

    # 6. Удаляем существующие блоки [Socks5] / [Http], очищаем от CRLF (\r)
    tr -d '\r' < "$TMP_DECODED" | awk '
        BEGIN { skip=0 }
        tolower($0) ~ /^\[(socks5|http)\]/ { skip=1 }
        skip && /^\[/ && tolower($0) !~ /^\[(socks5|http)\]/ { skip=0 }
        !skip { print }
    ' > "$FINAL_CONFIG_PATH"

    rm -f "$TMP_DECODED"

    # 7. Дописываем секции встроенного прокси wireproxy
    cat << EOF >> "$FINAL_CONFIG_PATH"

[Socks5]
BindAddress = ${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}

[Http]
BindAddress = ${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_HTTP}
EOF

    chmod 600 "$FINAL_CONFIG_PATH"
    echo -e "${GREEN}Рабочий файл конфигурации готов: $FINAL_CONFIG_PATH${NC}"

    # 8. Активация автозапуска службы
    ln -sf "$TEMPLATE_INIT" "$SYSTEM_INIT_PATH"
    chmod +x "$TEMPLATE_INIT" "$SYSTEM_INIT_PATH"

    echo "Перезапуск службы wireproxy-awg..."
    "$SYSTEM_INIT_PATH" restart
    sleep 2

    # 9. Интеграция с KeeneticOS RCI API
    echo "Интеграция с KeeneticOS API (обновление интерфейса)..."
    curl -s -d '[{"interface": { "name": "'${KEENETIC_PROXY_NAME}'","no": true }}]' "localhost:79/rci/" > /dev/null 2>&1

    API_DATA='[{
        "interface": {
            "name": "'${KEENETIC_PROXY_NAME}'",
            "description": "'${KEENETIC_PROXY_DESC}'",
            "proxy": {
                "protocol": { "proto": "'${PROXY_PROTO}'" },
                "upstream": { "host": "'${PROXY_LOCAL_IP}'", "port": "'${PROXY_LOCAL_PORT_SOCKS}'" },
                "socks5-udp": true
            }
        },
        "system": { "configuration": { "save": true } }
    }]'

    curl -s -d "${API_DATA}" "localhost:79/rci/" > /dev/null 2>&1
    curl -s -d '[{"interface": {"name": "'${KEENETIC_PROXY_NAME}'", "up": true}}]' "localhost:79/rci/" > /dev/null 2>&1

    echo -e "${GREEN}Интерфейс '${KEENETIC_PROXY_DESC}' (${KEENETIC_PROXY_NAME}) успешно зарегистрирован в KeeneticOS!${NC}"
    echo -e "${YELLOW}Чтобы переключить маршруты Kvas на этот туннель, выполните:${NC}"
    echo -e "  ${BLUE}kvas vpn set${NC}"
    echo ""

    run_test
}

uninstall_packet() {
    echo "Деактивация и остановка служб..."
    [ -f "$SYSTEM_INIT_PATH" ] && "$SYSTEM_INIT_PATH" stop

    echo "Удаление прокси-интерфейса из KeeneticOS..."
    curl -s -d '[{"interface": { "name": "'${KEENETIC_PROXY_NAME}'","no": true },"system": {"configuration": {"save": true}}}]' "localhost:79/rci/" > /dev/null 2>&1

    echo "Удаление симлинков и файлов пакета..."
    rm -f /opt/bin/kvas-awg /opt/bin/wireproxy "$SYSTEM_INIT_PATH" "$PIDFILE" "$LOGFILE"
    rm -rf "$FINAL_CONFIG_DIR" "$APP_BASE"
    echo -e "${GREEN}Пакет kvas-awg успешно и полностью удален.${NC}"
}

show_log() {
    if [ -f "$LOGFILE" ]; then
        echo "=== Журнал $LOGFILE (последние 40 строк) ==="
        tail -n 40 "$LOGFILE"
    else
        echo "Журнал $LOGFILE пуст или не создан."
    fi
}

case "$1" in
    install)    install_wireproxy ;;
    uninstall)  uninstall_packet ;;
    add)        add_config "$2" ;;
    test)       run_test ;;
    log)        show_log ;;
    start|restart)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" "$1"
            sleep 2
            run_test
        else
            echo -e "${RED}Ошибка: Служба не инициализирована. Сначала выполните: kvas-awg add \"vpn://...\"${NC}"
        fi
        ;;
    stop)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" "stop"
        else
            echo -e "${RED}Ошибка: Служба не инициализирована.${NC}"
        fi
        ;;
    *)
        show_status
        ;;
esac
