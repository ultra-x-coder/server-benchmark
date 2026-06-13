# benchx — бенчмарк производительности сервера (Linux / macOS)

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-121011?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white)
![RHEL/CentOS](https://img.shields.io/badge/RHEL%2FCentOS-EE0000?logo=redhat&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white)
![Arch](https://img.shields.io/badge/Arch-1793D1?logo=archlinux&logoColor=white)
![openSUSE](https://img.shields.io/badge/openSUSE-73BA25?logo=opensuse&logoColor=white)
![No agent](https://img.shields.io/badge/agent-not_required-success)

[English](README.md) · [简体中文](README.zh.md) · **Русский** · [한국어](README.ko.md) · [日本語](README.ja.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Español](README.es.md)

Один bash-скрипт, который измеряет CPU, RAM, диск, сеть и реальную производительность под
**nginx / redis / mongodb / node.js**. Ставит зависимости сам, печатает аккуратный отчёт в терминал,
сохраняет JSON и умеет сравнивать два сервера. Разработан так, чтобы быть **безопасным для запуска на боевых серверах**.

```bash
chmod +x benchx.sh
./benchx.sh            # стандартный прогон (~5 мин)
./benchx.sh --safe     # безопасный для прода прогон (рекомендуется на боевых серверах)
```

## Запуск на боевых серверах

Используйте **`--safe`** (сначала посмотрите план через `--dry-run`):

```bash
./benchx.sh --safe --dry-run   # показать, что именно произойдёт, и выйти
./benchx.sh --safe             # безопасный прогон
./benchx.sh --safe --skip disk # безопасный прогон вообще без записи на диск
```

Гарантии `--safe`:

- **никаких установок пакетов, никакого `sudo`, никаких изменений сервисов** — конфиги `/etc` и работающие демоны не трогаются;
- **низкий приоритет CPU/IO** (`nice 19` + `ionice -c3`) — прод сохраняет процессор и диск;
- **сеть только latency** (только ping, без насыщения полосы);
- **пропуск длительного stress-теста под полной нагрузкой**;
- **запись только в приватный temp** (+ `--json`), существующие файлы **никогда не перезаписываются**;
- **дисковый тест сначала проверяет свободное место** и уменьшается/пропускается, а не заполняет диск.

Эти меры действуют и вне `--safe`, где это важно: скрипт не перезаписывает существующий `--json` (без `--yes`),
не трогает существующие файлы (пишет только в уникальные temp-пути), проверяет место перед дисковым тестом,
поднимает app-серверы на `127.0.0.1` на случайном высоком порту, а **Ctrl-C мгновенно останавливает его и убирает
за собой** (без осиротевших серверов и temp-файлов).

## Что измеряется

| Категория | Метрики | Инструменты |
|-----------|---------|-------------|
| **CPU** | single-core, multi-core, масштабирование по потокам, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | полоса записи/чтения (1 поток и многопоточно), полоса memcpy, **латентность случайного доступа** (нс) | `sysbench`, `mbw`, компилируемый pointer-chase |
| **Диск** | тип (NVMe/SSD/HDD), random read/write IOPS (4k, qd32), последовательные read/write (МБ/с), латентность | `fio` (fallback: `dd` + `ioping`) |
| **Сеть** | download / upload (Мбит/с), idle-latency, ping/jitter/loss до 1.1.1.1 и 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, опц. `iperf3` |
| **Приложения** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx статика req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Дополнительно** | context-switch/threads, стабильность под нагрузкой (троттлинг), спавн процессов | `sysbench`, builtin |

### Workload-индексы

В конце считаются нормированные индексы (≈1000 = референсный облачный vCPU, выше = быстрее) для
**nginx / redis / mongodb / node.js** и общий. Каждый индекс — взвешенная комбинация первичных метрик
(например, для redis: single-core 40% + латентность RAM 25% + полоса RAM 10% + реальный redis GET 25%).
Индекс показывается, **только если реальный бенчмарк движка действительно выполнялся** — если `mongod`
недоступен, индекс MongoDB не появится. Именно эти индексы удобно сравнивать между серверами.

## Использование

```bash
./benchx.sh                       # стандарт (~5 мин)
./benchx.sh --quick               # быстро (~1-2 мин)
./benchx.sh --thorough            # тщательно (~15 мин)
./benchx.sh --safe                # безопасно для прода
./benchx.sh --dry-run             # показать план и выйти (ничего не делая)
./benchx.sh --no-install          # только наличные инструменты (ничего не ставить, без вопросов)
./benchx.sh --net-mode none       # пропустить сетевой тест
./benchx.sh --json server-a.json  # сохранить отчёт
./benchx.sh --only cpu,ram        # только эти категории
./benchx.sh --skip apps,net       # пропустить категории
```

### Сравнение двух серверов

```bash
# на сервере A:
./benchx.sh --json a.json
# на сервере B:
./benchx.sh --json b.json
# где угодно:
./benchx.sh --compare a.json b.json
```

Покажет таблицу метрик и индексов с разницей в % (зелёный = B быстрее, красный = медленнее).

## Опции

| Флаг | Назначение |
|------|-----------|
| `--quick` / `--thorough` | профиль длительности (по умолчанию standard, ~5 мин) |
| `--safe` | безопасно для прода: без установок/sudo/изменения сервисов, низкий приоритет CPU/IO, сеть только latency, пропуск stress-теста, не перезаписывает файлы |
| `--dry-run` | показать, что именно произойдёт, и выйти (ничего не меняя и не запуская) |
| `--no-install` | работать только с наличными инструментами: ничего не ставить, без sudo, без вопросов |
| `--reinstall` | принудительно переустановить нужные пакеты (также чинит «битый» dpkg после Ctrl-C) |
| `--confirm-each` | спрашивать перед установкой/переустановкой каждого пакета |
| `--yes` / `-y` | соглашаться на всё: без вопросов; также разрешает перезапись существующего `--json` |
| `--net-mode MODE` | режим сетевого теста: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | адрес своего iperf3-сервера (включает `--net-mode iperf`) |
| `--target DIR` | каталог для дискового теста (по умолчанию `.`) |
| `--only CSV` / `--skip CSV` | фильтр категорий: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | путь для JSON-отчёта |
| `--no-color` | без цвета (также уважается `NO_COLOR`) |
| `--compare A.json B.json` | сравнить два отчёта и выйти |
| `-h` / `--help` | справка |

## Зависимости и root

Скрипт сам определяет пакетный менеджер (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` на Linux, `brew` на macOS)
и доставляет недостающее.

- На Linux установка системных пакетов требует **root** — скрипт **один раз** спросит разрешение на `sudo`.
- При отказе (или с `--no-install`/`--safe`) используется только то, что доступно **без root**, остальное
  аккуратно пропускается с пометкой. Официальный **Ookla `speedtest` CLI ставится из tarball без root**
  (в `~/.local/bin`).
- На macOS `brew` root не требует.
- `--reinstall` чинит «битое» состояние `dpkg` (например, после прерванного `apt`) и переустанавливает пакеты.
  Сначала показывает **крупное предупреждение** — переустановка может перезаписать ваши конфиги в `/etc` и
  перезапустить сервисы; данные не удаляются, но на боевом сервере предпочтительнее `--no-install`/`--safe`.

Любая недоступная метрика просто пропускается (✓ выполнено, ∅ пропущено, ✗ ошибка) — скрипт не падает.

## Требования

- `bash` (совместим с 3.2 — дефолтный на macOS), стандартные утилиты.
- Для `--compare` нужен `python3` **или** `jq`.
- Для латентности RAM нужен компилятор C (`cc`/`gcc`/`clang`) — иначе метрика пропускается.

## JSON-отчёт

```jsonc
{
  "benchx_version": "1.0.0",
  "timestamp": "2026-06-13T09:49:21Z",
  "profile": "quick",
  "os": "Linux", "arch": "x86_64",
  "system": { "CPU": "...", "Cores/threads": "...", "RAM": "..." },
  "metrics": {
    "cpu": { "single_core_eps": {"value": 1234.5, "unit": "ev/s", "label": "Single-core", "higher_is_better": 1} },
    "ram": { "latency_ns": {"value": 72.6, "unit": "ns", "higher_is_better": 0} }
  },
  "scores": { "redis": 2303, "nginx": 1180, "overall": 1450 }
}
```

## Замечания по точности

- Запускайте на незанятой машине; на «шумных соседях» (виртуализация) результаты прыгают — используйте `--thorough`.
  Учтите: `--safe` работает с низким приоритетом, поэтому его числа отражают свободную ёмкость, а не пиковую.
- Дисковый тест пишет уникальный временный файл в `--target` (по умолчанию текущий каталог) и удаляет его.
- Speedtest обращается к внешним серверам Ookla; используйте `--net-mode latency` или `--net-mode none`, если это нежелательно.
- App-бенчмарки поднимают сервисы на `127.0.0.1` на случайном высоком порту и гасят их по завершении.

## Лицензия

MIT
