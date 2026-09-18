#!/bin/sh
set -e

REPO="jobgomel/kvas-awg"
APPS_DIR="/opt/apps/kvas-awg"
TMP_DIR="/tmp/kvas-awg-install-$$"
TMP_ZIP="${TMP_DIR}/package.zip"
DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_VER="$1"

# 1. Вывод всех доступных тегов через GitHub API
list_versions() {
    echo "Запрос списка версий из репозитория ${REPO}..."
    TAGS=$(curl -sL "https://api.github.com/repos/${REPO}/tags" | \
           grep -oE '"name": *"[^"]+"' | cut -d'"' -f4)

    if [ -z "$TAGS" ]; then
        echo "Ошибка: Не удалось получить список тегов через GitHub API."
        exit 1
    fi

    echo "Доступные версии для установки:"
    echo "$TAGS" | sed 's/^/  * /'
}

if [ "$TARGET_VER" = "list" ] || [ "$TARGET_VER" = "-l" ] || [ "$TARGET_VER" = "--list" ]; then
    list_versions
    exit 0
fi

echo "=== Установка пакета kvas-awg (AmneziaWG 3.1) ==="

# 2. Создание структуры папок
mkdir -p "${APPS_DIR}/bin" "${APPS_DIR}/etc/conf" "${APPS_DIR}/etc/init.d" "${APPS_DIR}/etc/ndm" "/opt/etc/awg"

# 3. Установка из локального каталога или загрузка из GitHub
if [ -d "$DIR/src" ]; then
    echo "Установка компонентов из локального каталога..."
    cp -rf "$DIR/src/"* "${APPS_DIR}/"
else
    # Определение версии для загрузки
    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" = "latest" ]; then
        echo "Поиск последнего релиза (latest)..."
        TARGET_TAG=$(curl -sI "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
                    tr -d '\r' | sed -n -E 's/^[Ll]ocation:.*\/tag\/([^[:space:]]+).*/\1/p' | head -n 1)

        if [ -z "$TARGET_TAG" ]; then
            # Резервный запрос через API, если редирект не сработал
            TARGET_TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
                        grep -oE '"tag_name": *"[^"]+"' | head -n 1 | cut -d'"' -f4)
        fi

        if [ -z "$TARGET_TAG" ]; then
            echo "Ошибка: Не удалось определить последний тег."
            exit 1
        fi
        echo "Выбрана последняя стабильная версия: ${TARGET_TAG}"
    else
        TARGET_TAG="$TARGET_VER"
        echo "Запрошена установка версии: ${TARGET_TAG}"
    fi

    ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/${TARGET_TAG}.zip"
    mkdir -p "$TMP_DIR"

    # Загрузка архива (с проверкой наличия префикса 'v')
    if ! curl -sL -f -o "$TMP_ZIP" "$ARCHIVE_URL" 2>/dev/null; then
        if [ "${TARGET_TAG#v}" = "$TARGET_TAG" ]; then
            ALT_TAG="v${TARGET_TAG}"
            ALT_URL="https://github.com/${REPO}/archive/refs/tags/${ALT_TAG}.zip"
            if curl -sL -f -o "$TMP_ZIP" "$ALT_URL" 2>/dev/null; then
                TARGET_TAG="$ALT_TAG"
                ARCHIVE_URL="$ALT_URL"
            fi
        fi
    fi

    if [ ! -s "$TMP_ZIP" ]; then
        echo "Ошибка: Не удалось скачать релиз '${TARGET_TAG}' (${ARCHIVE_URL})."
        echo "Для просмотра доступных версий выполните команду: install.sh list"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "Распаковка архива версии ${TARGET_TAG}..."
    unzip -qo "$TMP_ZIP" -d "$TMP_DIR"

    SRC_PATH=$(find "$TMP_DIR" -type d -name "src" | head -n 1)
    if [ -n "$SRC_PATH" ] && [ -d "$SRC_PATH" ]; then
        cp -rf "$SRC_PATH/"* "${APPS_DIR}/"
    else
        echo "Ошибка: В архиве не найдена директория src."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    rm -rf "$TMP_DIR"
fi

# 4. Назначение прав и создание системного симлинка
chmod +x "${APPS_DIR}/bin/manager.sh"
chmod +x "${APPS_DIR}/etc/init.d/S99awg"
chmod +x "${APPS_DIR}/etc/ndm/"*.sh 2>/dev/null || true

ln -sf "${APPS_DIR}/bin/manager.sh" /opt/bin/kvas-awg

# 5. Установка или обновление бинарника wireproxy-awg
if [ ! -f "${APPS_DIR}/bin/wireproxy" ]; then
    /opt/bin/kvas-awg install
else
    ln -sf "${APPS_DIR}/bin/wireproxy" /opt/bin/wireproxy
    /opt/bin/kvas-awg
fi