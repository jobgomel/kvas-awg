#!/bin/sh

REPO_RAW="https://raw.githubusercontent.com/jobgomel/kvas-awg/main"
APPS_DIR="/opt/apps/kvas-awg"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Установка пакета kvas-awg (AmneziaWG 3.1) ==="

# 1. Создание изолированной структуры папок
mkdir -p "${APPS_DIR}/bin"
mkdir -p "${APPS_DIR}/etc/conf"
mkdir -p "${APPS_DIR}/etc/init.d"
mkdir -p "${APPS_DIR}/etc/ndm"
mkdir -p "/opt/etc/awg"

# 2. Локальная установка из распакованного архива или загрузка из репозитория
if [ -d "$DIR/src" ]; then
    echo "Установка компонентов из локальных файлов..."
    cp -f "$DIR/src/bin/manager.sh" "${APPS_DIR}/bin/"
    cp -f "$DIR/src/etc/conf/env.sh" "${APPS_DIR}/etc/conf/"
    cp -f "$DIR/src/etc/conf/template.conf" "${APPS_DIR}/etc/conf/" 2>/dev/null || true
    cp -f "$DIR/src/etc/init.d/S99awg" "${APPS_DIR}/etc/init.d/"
    cp -f "$DIR/src/etc/ndm/check_space.sh" "${APPS_DIR}/etc/ndm/"
    cp -f "$DIR/src/etc/ndm/test_connection.sh" "${APPS_DIR}/etc/ndm/"
    if [ -f "$DIR/src/bin/wireproxy" ]; then
        cp -f "$DIR/src/bin/wireproxy" "${APPS_DIR}/bin/"
        chmod +x "${APPS_DIR}/bin/wireproxy"
    fi
else
    echo "Загрузка управляющего скрипта и шаблонов из репозитория..."
    curl -sL -o "${APPS_DIR}/bin/manager.sh" "${REPO_RAW}/src/bin/manager.sh"
    curl -sL -o "${APPS_DIR}/etc/conf/env.sh" "${REPO_RAW}/src/etc/conf/env.sh"
    curl -sL -o "${APPS_DIR}/etc/conf/template.conf" "${REPO_RAW}/src/etc/conf/template.conf"
    curl -sL -o "${APPS_DIR}/etc/init.d/S99awg" "${REPO_RAW}/src/etc/init.d/S99awg"
    curl -sL -o "${APPS_DIR}/etc/ndm/check_space.sh" "${REPO_RAW}/src/etc/ndm/check_space.sh"
    curl -sL -o "${APPS_DIR}/etc/ndm/test_connection.sh" "${REPO_RAW}/src/etc/ndm/test_connection.sh"
fi

# Проверка файлов
if [ ! -s "${APPS_DIR}/bin/manager.sh" ] || grep -q "404:" "${APPS_DIR}/bin/manager.sh"; then
    echo "Ошибка: Не удалось подготовить файлы менеджера."
    exit 1
fi

chmod +x "${APPS_DIR}/bin/manager.sh"
chmod +x "${APPS_DIR}/etc/init.d/S99awg"
chmod +x "${APPS_DIR}/etc/ndm/check_space.sh"
chmod +x "${APPS_DIR}/etc/ndm/test_connection.sh"

# 3. Создание системного симлинка
ln -sf "${APPS_DIR}/bin/manager.sh" /opt/bin/kvas-awg

# 4. Запуск внутренней установки бинарника wireproxy-awg
if [ ! -f "${APPS_DIR}/bin/wireproxy" ]; then
    /opt/bin/kvas-awg install
else
    ln -sf "${APPS_DIR}/bin/wireproxy" /opt/bin/wireproxy
    /opt/bin/kvas-awg
fi
