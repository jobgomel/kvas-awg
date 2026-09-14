# Kvas-AmneziaWG (kvas-awg) 🛡️

Модульное расширение для менеджера маршрутизации **Kvas** ([qzeleza/kvas](https://github.com/qzeleza/kvas)), добавляющее поддержку протокола **AmneziaWG 3.1** (а также 1.0, 2.0 и 3.0)
на роутерах Keenetic с развернутой средой Entware.

Построено по модульной архитектуре аналогично пакету **kvas-hysteria** ([jobgomel/kvas-hysteria](https://github.com/jobgomel/kvas-hysteria)),
но использует полностью userspace-движок `wireproxy-awg` ([artem-russkikh/wireproxy-awg](https://github.com/artem-russkikh/wireproxy-awg)).
Не требует компиляции или загрузки сторонних модулей ядра (`kmod-amneziawg`), работает стабильно на любых ревизиях ядра KeeneticOS
и не затрагивает встроенный в прошивку стек WireGuard.

---

## ✨ Возможности и особенности

* **Поддержка AmneziaWG 3.1:** Все актуальные параметры обфускации и защиты от DPI:
  * `HeaderProtectionKey`
  * `ContentPaddingAddition`
  * `RandomTrailers`, `DisableCookies`
  * Диапазоны заголовков `H1`–`H4` и таймингов (`RekeyAfterTime`, `PersistentKeepalive` и др.)
  * Базовые параметры AWG 1.0/2.0 (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`)
* **Автоматический парсер ссылок:** Поддерживает форматы:
  * `vpn://W0ludGVyZmF...` (Base64-представление .conf файла)
  * `awg://W0ludGVyZmF...` / `amnezia://...`
  * Прямая Base64-строка
  * Локальный файл `.conf` (`kvas-awg add /opt/etc/awg/client.conf`)
  * Прямая ссылка HTTP/HTTPS на конфигурационный файл
* **Бесшовная интеграция с KeeneticOS и Kvas:** 
  * Автоматически регистрирует прокси-интерфейс `Proxy42` (`Kvas-proxy-awg`) через RCI API (`localhost:79/rci/`).
  * Для переключения трафика достаточно выполнить `kvas vpn set`.
* **Совместимость с Hysteria 2:** 
  * Использует порты `10818` (SOCKS5) и `10819` (HTTP), имя интерфейса `Proxy42`. Пакеты `kvas-hysteria` (порт 10808, `Proxy41`) и `kvas-awg` могут быть установлены параллельно на одном роутере без взаимных конфликтов.
* **Автоопределение архитектуры процессора:** Автоматически скачивает и верифицирует нужный бинарник `wireproxy-awg` под платформы Keenetic:
  * `mipsle` (MediaTek MT7621AT, MT7628, EN7512, EN7516 — большинство роутеров Keenetic)
  * `arm` (ARMv7 32-bit: Cortex-A7 / Cortex-A9, например Ultra KN-1810, Giga KN-1010)
  * `arm64` (AArch64: Cortex-A53, например Ultra KN-1811, Titan KN-1812, Peak KN-2710)
  * `amd64` / `386` (для x86/x64 платформ)

---

## 🛠 Установка

### Вариант 1. Через curl (из репозитория GitHub)
```bash
curl -sL https://raw.githubusercontent.com/jobgomel/kvas-awg/main/install.sh | sh
```

### Вариант 2. Из архива (офлайн / распаковка на роутере)
1. Распакуйте архив в любую временную папку на роутере:
   ```bash
   unzip kvas-awg-1.0.0.zip
   cd kvas-awg-1.0.0
   chmod +x install.sh
   ./install.sh
   ```
2. Скрипт создаст структуру папок в `/opt/apps/kvas-awg`, настроит системный симлинк `/opt/bin/kvas-awg` и скачает бинарник `wireproxy-awg`.

---

## 🚀 Использование и управление

Управление осуществляется через CLI утилиту `kvas-awg`.

### 1. Добавление конфигурации
Передайте ссылку или файл команде `add`:
```bash
# Импорт ссылки vpn:// (кавычки обязательны!)
kvas-awg add "vpn://W0ludGVyZmFjZV0KUHJpdmF0ZUtleSA9..."

# Или импорт файла конфигурации:
kvas-awg add /opt/etc/awg/client.conf
```
Скрипт автоматически:
1. Распарсит параметры AmneziaWG 3.1.
2. Сконфигурирует локальный SOCKS5 на `127.0.0.1:10818`.
3. Сохранит конфигурацию в `/opt/etc/awg/awg.conf`.
4. Зарегистрирует интерфейс `Proxy42 (Kvas-proxy-awg)` в KeeneticOS.
5. Перезапустит службу и проведет экспресс-тест соединения.

### 2. Подключение к Kvas
После добавления туннеля переключите Kvas на новый интерфейс:
```bash
kvas vpn set
```
В интерактивном меню выберите интерфейс **Proxy42 (Kvas-proxy-awg)**.

### 3. Экспресс-тест
Проверка доступности интернета и внешнего IP-адреса через туннель:
```bash
kvas-awg test
```

### 4. Управление службой
```bash
kvas-awg start      # Запуск туннеля
kvas-awg stop       # Остановка
kvas-awg restart    # Перезапуск
kvas-awg status     # Текущее состояние процесса и активный Endpoint
kvas-awg log        # Просмотр последних строк журнала работы
```

### 5. Удаление пакета
Для полного удаления службы, бинарников и созданного прокси-интерфейса из KeeneticOS:
```bash
kvas-awg uninstall
```

---

## 📁 Структура каталогов

```text
/opt/apps/kvas-awg/
├── bin/
│   ├── manager.sh              # Главный CLI-инструмент управления
│   └── wireproxy               # Бинарный файл wireproxy-awg
└── etc/
    ├── conf/
    │   ├── env.sh              # Переменные среды, порты и имена интерфейсов
    │   └── template.conf       # Пример структуры конфига AWG 3.1
    ├── init.d/
    │   └── S99awg              # Служба автозапуска Entware
    └── ndm/
        ├── check_space.sh      # Проверка свободного места
        └── test_connection.sh  # Скрипт тестирования проксирования

/opt/etc/awg/
└── awg.conf                    # Рабочая конфигурация AmneziaWG 3.1
```
