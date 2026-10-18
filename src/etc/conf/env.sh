#!/bin/sh

# Подключение системных констант приложения
[ -f /opt/apps/kvas-awg/etc/conf/const.sh ] && . /opt/apps/kvas-awg/etc/conf/const.sh

# Параметры локального прокси-сервера AmneziaWG (wireproxy)
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT_SOCKS=10818

# Профиль использования ресурсов (eco | balanced | perf | custom)
RESOURCE_PROFILE="balanced"

# Ограничение ресурсов Go Runtime для wireproxy
# GOMAXPROCS: ограничивает число ядер/потоков планировщика (снижает количество потоков ОС)
# GOMEMLIMIT: мягкий лимит памяти Go Runtime (GC активнее сбрасывает память при приближении к лимиту)
# GOGC: процент роста кучи перед запуском сборщика мусора (меньше значение = чаще GC)
# GODEBUG: немедленный возврат свободных страниц памяти ядру Linux через MADV_DONTNEED
GOMAXPROCS=2
GOMEMLIMIT="24MiB"
GOGC=25
GODEBUG="madvdontneed=1"

# Уровень логирования wireproxy (silent | debug)
LOG_LEVEL="silent"
