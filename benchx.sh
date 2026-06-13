#!/usr/bin/env bash
# benchx.sh — кросс-платформенный (Linux/macOS) бенчмарк производительности сервера.
#
# Измеряет: CPU (single/multi, crypto, стабильность под нагрузкой), RAM (полоса + латентность),
# диск (тип, IOPS, throughput, латентность percentiles), сеть (speedtest + ping),
# а также реальные мини-бенчмарки redis / node / nginx / mongodb (hybrid).
# Считает «workload-индексы» (nginx/redis/mongodb/nodejs), чтобы сравнивать серверы.
#
# Зависимости ставит сам. Если нужен root — спросит один раз. При отказе делает что может без root.
#
# Использование:
#   ./benchx.sh                 # стандартный прогон (~5 мин)
#   ./benchx.sh --quick         # быстрый (~1-2 мин)
#   ./benchx.sh --thorough      # тщательный (~15 мин)
#   ./benchx.sh --no-net        # без сетевого теста
#   ./benchx.sh --net-mode iperf --iperf-host HOST
#   ./benchx.sh --no-install    # ничего не ставить, использовать только наличные инструменты
#   ./benchx.sh --yes           # не спрашивать про sudo (соглашаться)
#   ./benchx.sh --json out.json # путь для JSON-отчёта
#   ./benchx.sh --only cpu,ram  # только указанные категории
#   ./benchx.sh --skip net,apps # пропустить категории
#   ./benchx.sh --compare a.json b.json   # сравнить два отчёта
#
# Категории: cpu ram disk net apps extras

# ── гарантируем bash (на macOS sh != bash; перезапускаемся под bash) ────────────
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# Без -u намеренно: скрипт активно использует массивы, которые бывают пустыми, а bash 3.2
# (дефолт на macOS) под `set -u` падает на "${arr[@]}"/"${!arr[@]}" для пустого массива.
set -o pipefail
export LC_ALL=C LANG=C

VERSION="1.0.0"

# ── глобальные настройки по умолчанию ──────────────────────────────────────────
PROFILE="standard"          # quick | standard | thorough
DO_INSTALL=1                # ставить недостающее
REINSTALL=0                 # принудительно переустановить все нужные пакеты (--reinstall)
ASSUME_YES=0                # не спрашивать про sudo
NET_MODE="speedtest"        # speedtest | latency | iperf | none
IPERF_HOST=""
JSON_PATH=""
USE_COLOR=1
ONLY_CATS=""
SKIP_CATS=""
RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
WORKDIR=""                  # временный каталог
TARGET_DIR="."              # где тестировать диск (текущий каталог)
DISK_TESTDIR=""             # каталог дискового теста (для очистки в trap при Ctrl-C)

# профильные параметры (заполняются в apply_profile)
CPU_TIME=10; MEM_GB=10; DISK_SIZE="1G"; DISK_TIME=15
REDIS_N=200000; HTTP_DUR=8; THERMAL_TIME=30; MEMLAT_STEPS=100000000
MONGO_INS=50000; MONGO_FIND=10000

# ── разбор аргументов ──────────────────────────────────────────────────────────
COMPARE_A=""; COMPARE_B=""; MODE="run"

print_help() {
  cat <<'EOF'
benchx.sh — бенчмарк производительности сервера (Linux/macOS)

ОПЦИИ:
  --quick | --standard | --thorough   профиль длительности (по умолчанию standard)
  --no-net                             пропустить сетевой тест
  --net-mode MODE                      speedtest | latency | iperf | none
  --iperf-host HOST                    адрес своего iperf3-сервера (для --net-mode iperf)
  --target DIR                         каталог для дискового теста (по умолчанию .)
  --no-install                         не устанавливать зависимости
  --reinstall | --force-install        принудительно переустановить нужные пакеты (чинит «битый» dpkg после Ctrl-C)
  --yes                                соглашаться на sudo без вопросов
  --json PATH                          путь для JSON-отчёта
  --only CSV                           только эти категории: cpu,ram,disk,net,apps,extras
  --skip CSV                           пропустить эти категории
  --no-color                           без цвета
  --compare A.json B.json              сравнить два отчёта и выйти
  -h | --help                          эта справка
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --quick) PROFILE="quick" ;;
    --standard) PROFILE="standard" ;;
    --thorough) PROFILE="thorough" ;;
    --no-net) NET_MODE="none" ;;
    --net-mode) shift; NET_MODE="${1:-speedtest}" ;;
    --iperf-host) shift; IPERF_HOST="${1:-}"; NET_MODE="iperf" ;;
    --target) shift; TARGET_DIR="${1:-.}" ;;
    --no-install) DO_INSTALL=0 ;;
    --reinstall|--force-install) REINSTALL=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --json) shift; JSON_PATH="${1:-}" ;;
    --only) shift; ONLY_CATS="${1:-}" ;;
    --skip) shift; SKIP_CATS="${1:-}" ;;
    --no-color) USE_COLOR=0 ;;
    --compare) shift; COMPARE_A="${1:-}"; shift; COMPARE_B="${1:-}"; MODE="compare" ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Неизвестный аргумент: $1" >&2; print_help; exit 1 ;;
  esac
  shift
done

apply_profile() {
  case "$PROFILE" in
    quick)    CPU_TIME=5;  MEM_GB=4;  DISK_SIZE="512M"; DISK_TIME=8;  REDIS_N=100000; HTTP_DUR=5;  THERMAL_TIME=15; MEMLAT_STEPS=50000000;  MONGO_INS=20000;  MONGO_FIND=3000 ;;
    standard) CPU_TIME=10; MEM_GB=10; DISK_SIZE="1G";   DISK_TIME=15; REDIS_N=200000; HTTP_DUR=8;  THERMAL_TIME=30; MEMLAT_STEPS=100000000; MONGO_INS=50000;  MONGO_FIND=10000 ;;
    thorough) CPU_TIME=25; MEM_GB=20; DISK_SIZE="4G";   DISK_TIME=30; REDIS_N=500000; HTTP_DUR=15; THERMAL_TIME=60; MEMLAT_STEPS=200000000; MONGO_INS=100000; MONGO_FIND=20000 ;;
  esac
}
apply_profile

# ── определение TTY / цвета ─────────────────────────────────────────────────────
IS_TTY=0
if [ -t 1 ]; then IS_TTY=1; fi
if [ -n "${NO_COLOR:-}" ]; then USE_COLOR=0; fi
if [ "$IS_TTY" = 0 ]; then USE_COLOR=0; fi

if [ "$USE_COLOR" = 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'; C_GREY=$'\033[90m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GREY=""
fi

# ── утилиты ──────────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

die() { printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

# числа
is_num() {
  case "$1" in ''|*[!0-9.eE+-]*) return 1;; esac
  awk -v x="$1" 'BEGIN{ if (x ~ /^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$/) exit 0; exit 1 }'
}
fmt_num() { awk -v n="${1:-0}" -v d="${2:-2}" 'BEGIN{printf "%.*f", d, n}'; }
# целое с разделителями тысяч (пробел)
fmt_int() {
  awk -v n="${1:-0}" 'BEGIN{
    s=sprintf("%d", n); neg=""; if (substr(s,1,1)=="-"){neg="-"; s=substr(s,2)}
    r=""; c=0;
    for (i=length(s); i>=1; i--){ r=substr(s,i,1) r; c++; if (c%3==0 && i>1) r=" " r }
    print neg r
  }'
}
# делёж с защитой от нуля
fdiv() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ if(b==0){print 0}else{printf "%.6f", a/b} }'; }
fmul() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{printf "%.6f", a*b}'; }

# таймаут (на macOS нет timeout(1))
run_timeout() {
  local secs="$1"; shift
  if have timeout; then timeout "$secs" "$@"; return $?; fi
  if have gtimeout; then gtimeout "$secs" "$@"; return $?; fi
  # fallback: запускаем процесс, сторож убивает по таймауту.
  # ВАЖНО: fd сторожа перенаправлены в /dev/null — иначе его sleep держит
  # stdout-пайп command-substitution открытым и подстановка ждёт весь таймаут.
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  # гасим сторож и его дочерний sleep, чтобы не плодить осиротевшие процессы
  local kid; kid="$(pgrep -P "$watcher" 2>/dev/null)"
  kill -TERM "$watcher" 2>/dev/null
  [ -n "$kid" ] && kill -TERM $kid 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $rc
}

# ── спиннер / шаги ──────────────────────────────────────────────────────────
SPIN_PID=""; STEP_LABEL=""; STEP_START=0
SERVER_PIDS=""                       # PID поднятых серверов (redis/node/nginx/mongod) для подстраховочной очистки
reg_server() { SERVER_PIDS="$SERVER_PIDS $1"; }
spin_start() {
  STEP_LABEL="$1"; STEP_START="$(date +%s)"
  if [ "$IS_TTY" = 1 ]; then
    (
      local frames='|/-\'; local i=0
      while :; do
        i=$(( (i+1) % 4 ))
        printf '\r%s%s%s %s ' "$C_CYAN" "${frames:$i:1}" "$C_RESET" "$STEP_LABEL"
        sleep 0.12
      done
    ) &
    SPIN_PID=$!
    disown "$SPIN_PID" 2>/dev/null || true
  else
    printf '  - %s ... ' "$STEP_LABEL"
  fi
}
spin_end() {
  local st="${1:-ok}"; local msg="${2:-}"
  if [ -n "$SPIN_PID" ]; then
    kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; SPIN_PID=""
    printf '\r\033[K'
  fi
  local dur=$(( $(date +%s) - STEP_START ))
  local sym col
  case "$st" in
    ok)   sym="✓"; col="$C_GREEN" ;;
    skip) sym="∅"; col="$C_YELLOW" ;;
    fail) sym="✗"; col="$C_RED" ;;
    *)    sym="•"; col="$C_GREY" ;;
  esac
  printf '  %s%s%s %s %s(%ss)%s' "$col" "$sym" "$C_RESET" "$STEP_LABEL" "$C_GREY" "$dur" "$C_RESET"
  if [ -n "$msg" ]; then printf ' %s%s%s' "$C_DIM" "$msg" "$C_RESET"; fi
  printf '\n'
}

hr() { printf '%s%s%s\n' "$C_GREY" "────────────────────────────────────────────────────────────────────" "$C_RESET"; }

section() {
  printf '\n%s%s%s %s%s%s\n' "$C_BOLD" "$C_BLUE" "$1" "$C_BOLD" "$2" "$C_RESET"
}

# ── хранилище метрик (без assoc-массивов — bash 3.2 совместимо) ────────────────
M_CAT=(); M_KEY=(); M_VAL=(); M_UNIT=(); M_LABEL=(); M_HIGH=(); M_NOTE=()
metric_add() {
  # cat key value unit label higher_is_better(1/0) note
  M_CAT+=("$1"); M_KEY+=("$2"); M_VAL+=("$3"); M_UNIT+=("${4:-}")
  M_LABEL+=("$5"); M_HIGH+=("${6:-1}"); M_NOTE+=("${7:-}")
}

I_KEY=(); I_VAL=()
info_add() { I_KEY+=("$1"); I_VAL+=("$2"); }

SC_KEY=(); SC_VAL=(); SC_LABEL=(); SC_PROXY=()
score_add() { SC_KEY+=("$1"); SC_VAL+=("$2"); SC_LABEL+=("$3"); SC_PROXY+=("${4:-0}"); }

NOTES=()
note() { NOTES+=("$1"); }

# ── категории ──────────────────────────────────────────────────────────────────
cat_enabled() {
  local c="$1"
  if [ -n "$ONLY_CATS" ]; then
    case ",$ONLY_CATS," in *",$c,"*) ;; *) return 1;; esac
  fi
  if [ -n "$SKIP_CATS" ]; then
    case ",$SKIP_CATS," in *",$c,"*) return 1;; esac
  fi
  return 0
}

# ── определение ОС / пакетного менеджера ────────────────────────────────────────
OS="$(uname -s)"; ARCH="$(uname -m)"
PKG_MGR=""; PKG_INSTALL=""; PKG_UPDATE=""; NEEDS_ROOT=1
SUDO=""

detect_pkg() {
  case "$OS" in
    Darwin)
      if have brew; then PKG_MGR="brew"; PKG_INSTALL="brew install"; PKG_UPDATE=""; NEEDS_ROOT=0
      else PKG_MGR="none"; fi
      ;;
    Linux)
      if have apt-get; then PKG_MGR="apt"; PKG_INSTALL="apt-get install -y"; PKG_UPDATE="apt-get update"
      elif have dnf; then PKG_MGR="dnf"; PKG_INSTALL="dnf install -y"; PKG_UPDATE=""
      elif have yum; then PKG_MGR="yum"; PKG_INSTALL="yum install -y"; PKG_UPDATE=""
      elif have pacman; then PKG_MGR="pacman"; PKG_INSTALL="pacman -S --noconfirm"; PKG_UPDATE="pacman -Sy"
      elif have zypper; then PKG_MGR="zypper"; PKG_INSTALL="zypper install -y"; PKG_UPDATE=""
      elif have apk; then PKG_MGR="apk"; PKG_INSTALL="apk add"; PKG_UPDATE="apk update"
      else PKG_MGR="none"; fi
      ;;
    *) PKG_MGR="none" ;;
  esac

  if [ "$(id -u)" = "0" ]; then NEEDS_ROOT=0; SUDO=""; fi
  if [ "$NEEDS_ROOT" = 1 ] && have sudo; then SUDO="sudo"; fi
}

# имя пакета для инструмента в текущем менеджере; "" если не знаем
pkg_for() {
  local tool="$1"
  case "$PKG_MGR" in
    apt)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        mbw) echo mbw;; ioping) echo ioping;; iperf3) echo iperf3;;
        redis-server) echo redis-server;; redis-benchmark) echo redis-tools;;
        wrk) echo wrk;; node) echo nodejs;; nginx) echo nginx-light;;
        mongod) echo "";; jq) echo jq;; lshw) echo lshw;; openssl) echo openssl;;
        nproc) echo coreutils;; *) echo "";;
      esac;;
    dnf|yum)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        mbw) echo "";; ioping) echo ioping;; iperf3) echo iperf3;;
        redis-server) echo redis;; redis-benchmark) echo redis;;
        wrk) echo wrk;; node) echo nodejs;; nginx) echo nginx;;
        mongod) echo "";; jq) echo jq;; lshw) echo lshw;; openssl) echo openssl;; *) echo "";;
      esac;;
    pacman)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        mbw) echo "";; ioping) echo ioping;; iperf3) echo iperf3;;
        redis-server) echo redis;; redis-benchmark) echo redis;;
        wrk) echo wrk;; node) echo nodejs;; nginx) echo nginx;;
        mongod) echo "";; jq) echo jq;; lshw) echo lshw;; openssl) echo openssl;; *) echo "";;
      esac;;
    zypper)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        ioping) echo ioping;; iperf3) echo iperf;; redis-server) echo redis;;
        redis-benchmark) echo redis;; node) echo nodejs;; nginx) echo nginx;;
        jq) echo jq;; openssl) echo openssl;; *) echo "";;
      esac;;
    apk)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        ioping) echo ioping;; iperf3) echo iperf3;; redis-server) echo redis;;
        redis-benchmark) echo redis;; wrk) echo wrk;; node) echo nodejs;;
        nginx) echo nginx;; jq) echo jq;; openssl) echo openssl;; *) echo "";;
      esac;;
    brew)
      case "$tool" in
        sysbench) echo sysbench;; fio) echo fio;; stress-ng) echo stress-ng;;
        mbw) echo mbw;; ioping) echo ioping;; iperf3) echo iperf3;;
        redis-server) echo redis;; redis-benchmark) echo redis;;
        wrk) echo wrk;; node) echo node;; nginx) echo nginx;;
        mongod) echo "";; jq) echo jq;; speedtest) echo speedtest-cli;; openssl) echo openssl;; *) echo "";;
      esac;;
    *) echo "";;
  esac
}

# Состояние системного пакета: installed | broken | absent.
# Ловит «битый» пакет после прерванного apt (бинарь на месте, но пакет не сконфигурирован),
# из-за чего `command -v` врёт, что всё установлено.
pkg_state() {
  local pkg="$1"
  case "$PKG_MGR" in
    apt)
      local s; s="$(dpkg -s "$pkg" 2>/dev/null | awk -F': ' '/^Status:/{print $2; exit}')"
      if [ -z "$s" ]; then echo absent
      elif [ "$s" = "install ok installed" ]; then echo installed
      else echo broken; fi ;;
    dnf|yum|zypper) rpm -q "$pkg" >/dev/null 2>&1 && echo installed || echo absent ;;
    pacman) pacman -Qi "$pkg" >/dev/null 2>&1 && echo installed || echo absent ;;
    apk) apk info -e "$pkg" >/dev/null 2>&1 && echo installed || echo absent ;;
    *) echo installed ;;   # менеджер неизвестен — не вмешиваемся
  esac
}

# Установка Ookla speedtest CLI из официального tarball — БЕЗ root (бинарь в ~/.local/bin).
# https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-<arch>.tgz
ensure_speedtest() {
  tool_present speedtest && return 0
  local userbin="$HOME/.local/bin"; mkdir -p "$userbin" 2>/dev/null
  case ":$PATH:" in *":$userbin:"*) ;; *) PATH="$userbin:$PATH";; esac

  if [ "$OS" = "Linux" ] && { have curl || have wget; }; then
    local a url tgz
    case "$ARCH" in
      x86_64|amd64)  a="x86_64" ;;
      aarch64|arm64) a="aarch64" ;;
      armv7l|armhf)  a="armhf" ;;
      armv6l|armel)  a="armel" ;;
      i?86)          a="i386" ;;
      *)             a="" ;;
    esac
    if [ -n "$a" ]; then
      url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${a}.tgz"
      tgz="$WORKDIR/ookla-speedtest.tgz"
      spin_start "Установка Ookla speedtest ($a, без root)"
      if { have curl && curl -fsSL "$url" -o "$tgz"; } || { have wget && wget -qO "$tgz" "$url"; }; then
        tar -xzf "$tgz" -C "$WORKDIR" speedtest 2>/dev/null || tar -xzf "$tgz" -C "$WORKDIR" 2>/dev/null
        if [ -f "$WORKDIR/speedtest" ]; then
          install -m 0755 "$WORKDIR/speedtest" "$userbin/speedtest" 2>/dev/null \
            || { cp "$WORKDIR/speedtest" "$userbin/speedtest" && chmod +x "$userbin/speedtest"; }
          hash -r 2>/dev/null
          tool_present speedtest && { spin_end ok; return 0; }
        fi
        spin_end fail "не удалось распаковать"
      else
        spin_end fail "загрузка не удалась"
      fi
    fi
  fi

  # запасной путь (тоже без root, кроме brew): speedtest-cli
  if [ "$PKG_MGR" = brew ]; then
    spin_start "Установка speedtest (brew)"; brew install speedtest-cli >"$WORKDIR/brew_st.log" 2>&1 && spin_end ok || spin_end fail
  elif have pip3; then
    spin_start "Установка speedtest-cli (pip --user)"
    pip3 install --user speedtest-cli >"$WORKDIR/pip.log" 2>&1 && spin_end ok || spin_end fail
  else
    note "speedtest установить не удалось (нет curl/wget и pip3)."
  fi
}

# ── установка зависимостей ──────────────────────────────────────────────────────
WANT_TOOLS=()
want() { WANT_TOOLS+=("$1"); }

build_wishlist() {
  want jq
  cat_enabled cpu   && { want sysbench; want stress-ng; want openssl; }
  cat_enabled ram   && { want sysbench; want mbw; }
  cat_enabled disk  && { want fio; want ioping; }
  cat_enabled net   && {
    case "$NET_MODE" in
      speedtest) want speedtest ;;
      iperf) want iperf3 ;;
    esac
  }
  cat_enabled apps  && { want redis-server; want redis-benchmark; want node; want wrk; want nginx; }
  cat_enabled extras && { want stress-ng; want openssl; }
}

# уникализация списка
uniq_list() { printf '%s\n' "$@" | awk 'NF && !seen[$0]++'; }

INSTALL_FAILED=()  # что не удалось установить (для заметок)

tool_present() {
  case "$1" in
    speedtest) have speedtest || have speedtest-cli ;;
    *) have "$1" ;;
  esac
}

install_deps() {
  local missing=() t pkg
  build_wishlist
  local wl; wl="$(uniq_list "${WANT_TOOLS[@]}")"

  for t in $wl; do
    if [ "$REINSTALL" = 1 ]; then missing+=("$t"); continue; fi
    if tool_present "$t"; then
      # бинарь есть, но после прерванного apt пакет бывает «битым» — такой переустановим
      pkg="$(pkg_for "$t")"
      if [ -n "$pkg" ] && [ "$(pkg_state "$pkg")" = broken ]; then
        note "Пакет '$pkg' в незавершённом состоянии — переустановлю."
        missing+=("$t")
      fi
      continue
    fi
    missing+=("$t")
  done

  if [ "${#missing[@]}" = 0 ]; then
    note "Все необходимые инструменты уже установлены."
    return 0
  fi
  [ "$REINSTALL" = 1 ] && note "Режим --reinstall: принудительная переустановка нужных пакетов."

  if [ "$DO_INSTALL" = 0 ]; then
    note "Установка отключена (--no-install). Недостающее будет пропущено: ${missing[*]}"
    return 0
  fi

  if [ "$PKG_MGR" = "none" ]; then
    note "Пакетный менеджер не найден. Пропускаю установку: ${missing[*]}"
    return 0
  fi

  # speedtest ставим отдельно (Ookla tarball, без root); остальное — через пакетный менеджер
  local need_pkg=() want_speedtest=0
  for t in "${missing[@]}"; do
    if [ "$t" = "speedtest" ]; then want_speedtest=1; continue; fi
    pkg="$(pkg_for "$t")"
    if [ -n "$pkg" ]; then need_pkg+=("$pkg")
    else INSTALL_FAILED+=("$t"); fi
  done

  # запрос root при необходимости
  if [ "${#need_pkg[@]}" -gt 0 ] && [ "$NEEDS_ROOT" = 1 ]; then
    if [ "$ASSUME_YES" = 0 ]; then
      printf '\n%s⚙  Для установки нужны root-права (%s).%s\n' "$C_YELLOW" "$PKG_MGR" "$C_RESET"
      printf '   Пакеты: %s%s%s\n' "$C_BOLD" "$(uniq_list "${need_pkg[@]}" | tr '\n' ' ')" "$C_RESET"
      printf '   Установить через sudo? [y/N] '
      local ans=""
      # спрашиваем только при реальном интерактивном tty; в CI / curl|bash — не блокируемся, отказ от sudo
      if [ -t 0 ] && [ -r /dev/tty ]; then read -r ans </dev/tty || ans=""; else ans=""; fi
      case "$(lc "${ans:-n}")" in
        y|yes|д|да) ;;
        *) note "Отказ от sudo: системные пакеты пропущены (${need_pkg[*]}). Использую только наличное + non-root."; need_pkg=() ;;
      esac
    fi
  fi

  if [ "${#need_pkg[@]}" -gt 0 ]; then
    local plist; plist="$(uniq_list "${need_pkg[@]}" | tr '\n' ' ')"
    # команда установки (с учётом --reinstall)
    local inst="$PKG_INSTALL"
    if [ "$REINSTALL" = 1 ]; then
      case "$PKG_MGR" in
        apt)    inst="apt-get install -y --reinstall" ;;
        pacman) inst="pacman -S --noconfirm" ;;
        zypper) inst="zypper install -y --force" ;;
      esac
    fi
    spin_start "Установка пакетов: $plist"
    {
      # ремонт «битого» dpkg после прерванного apt (частые Ctrl-C на Ubuntu)
      if [ "$PKG_MGR" = apt ]; then
        $SUDO dpkg --configure -a
        $SUDO apt-get install -f -y
      fi
      if [ -n "$PKG_UPDATE" ]; then $SUDO $PKG_UPDATE; fi
      # shellcheck disable=SC2086
      $SUDO $inst $plist
    } >"$WORKDIR/install.log" 2>&1
    if [ $? -eq 0 ]; then spin_end ok; else spin_end fail "см. $WORKDIR/install.log"; note "Часть пакетов не установилась — будут пропущены."; fi
  fi

  # speedtest — официальный Ookla CLI из tarball (без root), с запасными путями внутри
  [ "$want_speedtest" = 1 ] && ensure_speedtest
}

# ── сбор системной информации ───────────────────────────────────────────────────
CPU_MODEL="?"; CPU_CORES=1; CPU_THREADS=1; CPU_MHZ=""; MEM_BYTES=0
collect_sysinfo() {
  local kernel; kernel="$(uname -r 2>/dev/null)"
  info_add "Хост" "$(hostname 2>/dev/null || echo '?')"
  info_add "ОС/Ядро" "$OS $kernel ($ARCH)"

  if [ "$OS" = "Darwin" ]; then
    CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '?')"
    CPU_CORES="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 1)"
    CPU_THREADS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)"
    local hz; hz="$(sysctl -n hw.cpufrequency 2>/dev/null || echo 0)"
    if [ "${hz:-0}" -gt 0 ] 2>/dev/null; then CPU_MHZ="$(fdiv "$hz" 1000000)"; fi
    MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    local prod; prod="$(sw_vers -productVersion 2>/dev/null || echo '')"
    [ -n "$prod" ] && info_add "macOS" "$prod"
  else
    if have lscpu; then
      CPU_MODEL="$(lscpu 2>/dev/null | awk -F: '/Model name/{sub(/^[ \t]+/,"",$2);print $2;exit}')"
      CPU_MHZ="$(lscpu 2>/dev/null | awk -F: '/^CPU max MHz|^CPU MHz/{gsub(/ /,"",$2);print $2;exit}')"
    fi
    [ -z "$CPU_MODEL" ] || [ "$CPU_MODEL" = "" ] && CPU_MODEL="$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null)"
    [ -z "$CPU_MODEL" ] && CPU_MODEL="?"
    CPU_THREADS="$(nproc 2>/dev/null || awk '/^processor/{c++}END{print c+0}' /proc/cpuinfo 2>/dev/null || echo 1)"
    CPU_CORES="$(awk -F: '/^core id/{print $2}' /proc/cpuinfo 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    [ -z "$CPU_CORES" ] || [ "$CPU_CORES" = "0" ] && CPU_CORES="$CPU_THREADS"
    MEM_BYTES="$(awk '/MemTotal/{print $2*1024; exit}' /proc/meminfo 2>/dev/null || echo 0)"
    local virt=""
    if have systemd-detect-virt; then virt="$(systemd-detect-virt 2>/dev/null)"; fi
    [ -n "$virt" ] && [ "$virt" != "none" ] && info_add "Виртуализация" "$virt"
  fi

  info_add "CPU" "$CPU_MODEL"
  local freq="?"; [ -n "$CPU_MHZ" ] && freq="$(fmt_num "$(fdiv "$CPU_MHZ" 1000)" 2) GHz"
  info_add "Ядра/потоки" "${CPU_CORES} / ${CPU_THREADS}${CPU_MHZ:+  @ $freq}"
  info_add "RAM" "$(fmt_num "$(fdiv "$MEM_BYTES" 1073741824)" 1) GiB"

  [ "${CPU_THREADS:-0}" -lt 1 ] 2>/dev/null && CPU_THREADS=1
  [ "${CPU_CORES:-0}" -lt 1 ] 2>/dev/null && CPU_CORES=1
}

# ── sysbench helpers (поддержка 1.x; fallback на 0.4) ──────────────────────────
SB_MAJOR=0
detect_sysbench() {
  have sysbench || { SB_MAJOR=0; return; }
  local v; v="$(sysbench --version 2>/dev/null | awk '{print $2}')"
  case "$v" in 1.*) SB_MAJOR=1;; 0.*) SB_MAJOR=04;; *) SB_MAJOR=1;; esac
}

# events/sec из sysbench cpu: threads time
sysbench_cpu() {
  local threads="$1" t="$2" out
  if [ "$SB_MAJOR" = 1 ]; then
    out="$(sysbench cpu --cpu-max-prime=20000 --threads="$threads" --time="$t" run 2>/dev/null)"
    printf '%s' "$out" | awk -F: '/events per second/{gsub(/ /,"",$2); print $2; found=1} END{if(!found)print ""}'
  else
    out="$(sysbench --test=cpu --cpu-max-prime=20000 --num-threads="$threads" --max-time="$t" run 2>/dev/null)"
    local ev tt
    ev="$(printf '%s' "$out" | awk '/total number of events/{print $NF; exit}')"
    tt="$(printf '%s' "$out" | awk '/total time:/{gsub(/s/,"",$NF);print $NF; exit}')"
    fdiv "${ev:-0}" "${tt:-1}"
  fi
}

# MiB/sec из sysbench memory: oper threads
sysbench_mem() {
  local oper="$1" threads="$2" out
  if [ "$SB_MAJOR" = 1 ]; then
    out="$(sysbench memory --memory-block-size=1M --memory-total-size=${MEM_GB}G \
           --memory-oper="$oper" --threads="$threads" run 2>/dev/null)"
  else
    out="$(sysbench --test=memory --memory-block-size=1M --memory-total-size=${MEM_GB}G \
           --memory-oper="$oper" --num-threads="$threads" run 2>/dev/null)"
  fi
  # строка вида: "  4096.00 MiB transferred (2730.66 MiB/sec)"
  printf '%s' "$out" | awk '/MiB\/sec|MB\/sec/{ for(i=1;i<=NF;i++) if($i ~ /\(/){gsub(/[()]/,"",$i); print $i; exit} }'
}

# openssl speed: возвращает пропускную способность для блока 16384 в MB/s
# (вывод openssl — в «1000s of bytes/sec» с суффиксом 'k'; снимаем 'k' и переводим)
ossl_speed_mbs() {
  local algo="$1" secs="${2:-1}" out v
  # OpenSSL 1.1+/3.x: -bytes ограничивает одним размером блока (быстрее)
  out="$(openssl speed -elapsed -seconds "$secs" -bytes 16384 "$algo" 2>/dev/null)"
  v="$(printf '%s' "$out" | awk -v a="^$algo" '$0 ~ a {x=$NF; sub(/k$/,"",x); print x; exit}')"
  if [ -z "$v" ]; then  # LibreSSL/старые: без -bytes, берём последнюю колонку (16384)
    out="$(openssl speed -elapsed -seconds "$secs" "$algo" 2>/dev/null)"
    v="$(printf '%s' "$out" | awk -v a="^$algo" '$0 ~ a {x=$NF; sub(/k$/,"",x); print x; exit}')"
  fi
  if [ -z "$v" ]; then  # совсем старые LibreSSL не понимают -seconds
    out="$(openssl speed -elapsed "$algo" 2>/dev/null)"
    v="$(printf '%s' "$out" | awk -v a="^$algo" '$0 ~ a {x=$NF; sub(/k$/,"",x); print x; exit}')"
  fi
  [ -z "$v" ] && { printf ''; return; }
  # openssl печатает «1000s of bytes/sec» (суффикс k): bytes/s = k*1000; MB/s = k*1000/1e6 = k/1000
  awk -v k="$v" 'BEGIN{printf "%.1f", k/1000}'
}

# ── CPU бенчмарк ────────────────────────────────────────────────────────────────
bench_cpu() {
  cat_enabled cpu || return 0
  section "🧮" "CPU"

  if have sysbench; then
    detect_sysbench
    spin_start "CPU single-core (sysbench, ${CPU_TIME}s)"
    local sc; sc="$(sysbench_cpu 1 "$CPU_TIME")"
    if is_num "$sc" && [ -n "$sc" ]; then
      metric_add cpu single_core_eps "$sc" "ev/s" "Single-core" 1
      spin_end ok "$(fmt_int "$sc") ev/s"
    else spin_end fail; fi

    spin_start "CPU multi-core (sysbench, ${CPU_THREADS}t, ${CPU_TIME}s)"
    local mc; mc="$(sysbench_cpu "$CPU_THREADS" "$CPU_TIME")"
    if is_num "$mc" && [ -n "$mc" ]; then
      metric_add cpu multi_core_eps "$mc" "ev/s" "Multi-core (${CPU_THREADS}t)" 1
      spin_end ok "$(fmt_int "$mc") ev/s"
      if is_num "${sc:-}" && [ -n "${sc:-}" ]; then
        metric_add cpu scaling_factor "$(fdiv "$mc" "$sc")" "x" "Масштабирование" 1
      fi
    else spin_end fail; fi
  elif ! have openssl; then
    note "sysbench/openssl недоступны — CPU-метрики пропущены."
  fi

  # crypto: AES-256 (важно для TLS у nginx) + SHA-256
  if have openssl; then
    local secs=1; [ "$PROFILE" = thorough ] && secs=2
    spin_start "Crypto AES-256-CBC (openssl)"
    local aes; aes="$(ossl_speed_mbs aes-256-cbc "$secs")"
    if is_num "$aes" && [ -n "$aes" ]; then metric_add cpu aes256_mbs "$aes" "MB/s" "AES-256-CBC (TLS)" 1; spin_end ok "$(fmt_int "$aes") MB/s"; else spin_end skip; fi

    spin_start "Crypto SHA-256 (openssl)"
    local sha; sha="$(ossl_speed_mbs sha256 "$secs")"
    if is_num "$sha" && [ -n "$sha" ]; then metric_add cpu sha256_mbs "$sha" "MB/s" "SHA-256" 1; spin_end ok "$(fmt_int "$sha") MB/s"; else spin_end skip; fi
  fi
}

# ── RAM бенчмарк ────────────────────────────────────────────────────────────────
bench_ram() {
  cat_enabled ram || return 0
  section "🧠" "RAM"

  if have sysbench; then
    detect_sysbench
    spin_start "RAM write throughput (sysbench)"
    local w; w="$(sysbench_mem write 1)"
    if is_num "$w" && [ -n "$w" ]; then metric_add ram write_mibs "$w" "MiB/s" "Запись (1 поток)" 1; spin_end ok "$(fmt_int "$w") MiB/s"; else spin_end fail; fi

    spin_start "RAM read throughput (sysbench)"
    local r; r="$(sysbench_mem read 1)"
    if is_num "$r" && [ -n "$r" ]; then metric_add ram read_mibs "$r" "MiB/s" "Чтение (1 поток)" 1; spin_end ok "$(fmt_int "$r") MiB/s"; else spin_end fail; fi

    spin_start "RAM throughput multi-thread (sysbench, ${CPU_THREADS}t)"
    local rmt; rmt="$(sysbench_mem read "$CPU_THREADS")"
    if is_num "$rmt" && [ -n "$rmt" ]; then metric_add ram read_mt_mibs "$rmt" "MiB/s" "Чтение (${CPU_THREADS}t)" 1; spin_end ok "$(fmt_int "$rmt") MiB/s"; else spin_end skip; fi
  fi

  # полоса через mbw (если есть)
  if have mbw; then
    spin_start "RAM bandwidth (mbw 256MiB)"
    local bw; bw="$(mbw -q -n 3 256 2>/dev/null | awk -F'[= ]+' '/AVG/{print $(NF-1); exit}')"
    if is_num "$bw" && [ -n "$bw" ]; then metric_add ram mbw_avg_mibs "$bw" "MiB/s" "mbw AVG (memcpy)" 1; spin_end ok "$(fmt_int "$bw") MiB/s"; else spin_end skip; fi
  fi

  # латентность через скомпилированный pointer-chase (если есть компилятор)
  bench_mem_latency
}

bench_mem_latency() {
  local cc=""
  if have cc; then cc=cc; elif have gcc; then cc=gcc; elif have clang; then cc=clang; fi
  if [ -z "$cc" ]; then note "Компилятор C не найден — латентность RAM пропущена."; return 0; fi

  local src="$WORKDIR/memlat.c" bin="$WORKDIR/memlat"
  cat >"$src" <<'CSRC'
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
/* pointer-chase: измеряет латентность случайного доступа к большому буферу */
int main(int argc, char **argv){
    size_t N = (size_t)64*1024*1024 / sizeof(size_t); /* 64 MiB рабочее множество */
    size_t *a = malloc(N*sizeof(size_t));
    if(!a) return 1;
    for(size_t i=0;i<N;i++) a[i]=i;
    /* перемешиваем (Fisher-Yates) для случайной цепочки */
    for(size_t i=N-1;i>0;i--){ size_t j=(size_t)((double)rand()/((double)RAND_MAX+1)*i); size_t t=a[i];a[i]=a[j];a[j]=t; }
    /* строим цепочку индексов */
    size_t *next = malloc(N*sizeof(size_t));
    if(!next) return 1;
    for(size_t i=0;i<N;i++) next[a[i]] = a[(i+1)%N];
    volatile size_t idx=0; size_t steps = (argc>1)? strtoull(argv[1],0,10) : 100000000UL;
    struct timespec t0,t1; clock_gettime(CLOCK_MONOTONIC,&t0);
    for(size_t i=0;i<steps;i++) idx=next[idx];
    clock_gettime(CLOCK_MONOTONIC,&t1);
    double ns=((double)(t1.tv_sec-t0.tv_sec)*1e9+(t1.tv_nsec-t0.tv_nsec))/(double)steps;
    printf("%.2f\n", ns);
    return (int)(idx & 1);
}
CSRC
  spin_start "RAM latency (pointer-chase 64MiB)"
  if "$cc" -O2 -o "$bin" "$src" >"$WORKDIR/cc.log" 2>&1; then
    local lat; lat="$(run_timeout 60 "$bin" "$MEMLAT_STEPS" 2>/dev/null)"
    if is_num "$lat" && [ -n "$lat" ]; then
      metric_add ram latency_ns "$lat" "ns" "Латентность (случайный доступ)" 0
      spin_end ok "${lat} ns"
    else spin_end skip; fi
  else spin_end skip "компиляция не удалась"; fi
}

# ── диск ──────────────────────────────────────────────────────────────────────
detect_disk_type() {
  if [ "$OS" = "Darwin" ]; then
    local dev kind
    dev="$(df "$TARGET_DIR" 2>/dev/null | awk 'NR==2{print $1}')"
    local info ssd proto
    info="$(diskutil info "$dev" 2>/dev/null)"
    ssd="$(printf '%s\n' "$info" | awk -F: '/Solid State/{gsub(/[ \t]/,"",$2);print $2;exit}')"
    proto="$(printf '%s\n' "$info" | awk -F: '/Protocol/{sub(/^[ \t]+/,"",$2);print $2;exit}')"
    case "$ssd" in Yes) kind="SSD";; No) kind="HDD";; *) kind="?";; esac
    [ -n "$proto" ] && kind="$kind ($proto)"
    info_add "Диск (тип)" "$kind"
  else
    local src dev rota
    src="$(df --output=source "$TARGET_DIR" 2>/dev/null | awk 'NR==2{print $1}')"
    [ -z "$src" ] && src="$(df "$TARGET_DIR" 2>/dev/null | awk 'NR==2{print $1}')"
    dev="$(basename "$src" 2>/dev/null)"
    # привести partition к базовому устройству
    local base; base="$(lsblk -no PKNAME "/dev/$dev" 2>/dev/null | head -1)"
    [ -n "$base" ] && dev="$base"
    case "$dev" in
      nvme*) info_add "Диск (тип)" "NVMe SSD (/dev/$dev)" ;;
      *)
        rota="$(cat "/sys/block/$dev/queue/rotational" 2>/dev/null)"
        [ -z "$rota" ] && rota="$(lsblk -ndo ROTA "/dev/$dev" 2>/dev/null | head -1)"
        if [ "$rota" = "0" ]; then info_add "Диск (тип)" "SSD (/dev/$dev)"
        elif [ "$rota" = "1" ]; then info_add "Диск (тип)" "HDD (/dev/$dev)"
        else info_add "Диск (тип)" "/dev/$dev (?)"; fi
        ;;
    esac
  fi
}

bench_disk() {
  cat_enabled disk || return 0
  section "💾" "Диск"
  detect_disk_type

  DISK_TESTDIR="$TARGET_DIR/.benchx_disk.$$"
  local testdir="$DISK_TESTDIR" mb lat
  mkdir -p "$testdir" 2>/dev/null || { note "Не удалось создать каталог для дискового теста в $TARGET_DIR"; DISK_TESTDIR=""; return 0; }

  if have fio; then
    local direct=1 ioeng="psync"
    if [ "$OS" = "Darwin" ]; then direct=0; ioeng="posixaio"; else
      # libaio предпочтительнее, если поддерживается
      if fio --enghelp 2>/dev/null | grep -q libaio; then ioeng="libaio"; fi
    fi
    local jq_or_py=""; have jq && jq_or_py=jq; have python3 && [ -z "$jq_or_py" ] && jq_or_py=py

    run_fio() { # name rw bs iodepth numjobs
      run_timeout $((DISK_TIME+20)) fio --name="$1" --directory="$testdir" --rw="$2" --bs="$3" \
        --size="$DISK_SIZE" --numjobs="$5" --iodepth="$4" --runtime="$DISK_TIME" --time_based \
        --direct="$direct" --ioengine="$ioeng" --group_reporting --output-format=json 2>/dev/null
    }
    fio_get() { # json field(read/write) metric(iops/bw_kb/lat_us)
      local j="$1" rw="$2" m="$3"
      if [ "$jq_or_py" = jq ]; then
        case "$m" in
          iops) printf '%s' "$j" | jq -r ".jobs[0].$rw.iops // empty" 2>/dev/null ;;
          bw_kb) printf '%s' "$j" | jq -r ".jobs[0].$rw.bw // empty" 2>/dev/null ;;
          lat_us) printf '%s' "$j" | jq -r ".jobs[0].$rw.lat_ns.mean // empty" 2>/dev/null | awk '{if($1!="")printf "%.2f",$1/1000}' ;;
          p99_us) printf '%s' "$j" | jq -r ".jobs[0].$rw.clat_ns.percentile[\"99.000000\"] // empty" 2>/dev/null | awk '{if($1!="")printf "%.2f",$1/1000}' ;;
        esac
      else
        printf '%s' "$j" | python3 -c "
import sys,json
try:
 d=json.load(sys.stdin); j=d['jobs'][0]['$rw']
 m='$m'
 if m=='iops': print(j.get('iops',''))
 elif m=='bw_kb': print(j.get('bw',''))
 elif m=='lat_us':
  v=j.get('lat_ns',{}).get('mean','')
  print(v/1000 if v!='' else '')
 elif m=='p99_us':
  v=j.get('clat_ns',{}).get('percentile',{}).get('99.000000','')
  print(v/1000 if v!='' else '')
except Exception: pass
" 2>/dev/null
      fi
    }

    spin_start "Диск: random read 4k (fio, qd32)"
    local j; j="$(run_fio randread randread 4k 32 1)"
    local v; v="$(fio_get "$j" read iops)"
    if is_num "$v" && [ -n "$v" ]; then
      metric_add disk randread_iops "$v" "IOPS" "4k random read" 1
      lat="$(fio_get "$j" read lat_us)"; is_num "$lat" && [ -n "$lat" ] && metric_add disk randread_lat_us "$lat" "µs" "  latency (avg)" 0
      spin_end ok "$(fmt_int "$v") IOPS"
    else spin_end skip; fi

    spin_start "Диск: random write 4k (fio, qd32)"
    j="$(run_fio randwrite randwrite 4k 32 1)"; v="$(fio_get "$j" write iops)"
    if is_num "$v" && [ -n "$v" ]; then
      metric_add disk randwrite_iops "$v" "IOPS" "4k random write" 1
      lat="$(fio_get "$j" write lat_us)"; is_num "$lat" && [ -n "$lat" ] && metric_add disk randwrite_lat_us "$lat" "µs" "  latency (avg)" 0
      spin_end ok "$(fmt_int "$v") IOPS"
    else spin_end skip; fi

    spin_start "Диск: sequential read 1M (fio)"
    j="$(run_fio seqread read 1M 16 1)"; v="$(fio_get "$j" read bw_kb)"
    # fio .bw в KiB/s -> десятичные MB/s = v*1024/1e6
    if is_num "$v" && [ -n "$v" ]; then mb="$(awk -v v="$v" 'BEGIN{printf "%.1f", v*1024/1000000}')"; metric_add disk seqread_mbs "$mb" "MB/s" "seq read (1M)" 1; spin_end ok "$(fmt_int "$mb") MB/s"; else spin_end skip; fi

    spin_start "Диск: sequential write 1M (fio)"
    j="$(run_fio seqwrite write 1M 16 1)"; v="$(fio_get "$j" write bw_kb)"
    if is_num "$v" && [ -n "$v" ]; then mb="$(awk -v v="$v" 'BEGIN{printf "%.1f", v*1024/1000000}')"; metric_add disk seqwrite_mbs "$mb" "MB/s" "seq write (1M)" 1; spin_end ok "$(fmt_int "$mb") MB/s"; else spin_end skip; fi
  else
    # fallback: dd sequential write
    spin_start "Диск: sequential write (dd, fallback)"
    local ddout mbps
    local ddconv=""; [ "$OS" = "Linux" ] && ddconv="conv=fdatasync"   # GNU dd: считать после сброса на диск
    ddout="$( { dd if=/dev/zero of="$testdir/ddtest" bs=1048576 count=1024 $ddconv 2>&1; sync; } )"
    # BSD: "... (6584141673 bytes/sec)"  |  GNU: "..., 2.1 GB/s"  — приводим к десятичным MB/s
    mbps="$(printf '%s\n' "$ddout" | sed -n 's/.*(\([0-9][0-9]*\) bytes\/sec).*/\1/p' | tail -1)"
    if [ -n "$mbps" ]; then mbps="$(awk -v b="$mbps" 'BEGIN{printf "%.1f", b/1000000}')"
    else
      mbps="$(printf '%s\n' "$ddout" | awk '/copied|bytes/{for(i=1;i<=NF;i++) if($i ~ /B\/s/){u=$i; v=$(i-1)+0; if(u ~ /GB/)m=v*1000; else if(u ~ /MB/)m=v; else if(u ~ /kB/)m=v/1000; else m=v/1000000; printf "%.1f",m; exit}}')"
    fi
    if is_num "$mbps" && [ -n "$mbps" ]; then metric_add disk seqwrite_mbs "$mbps" "MB/s" "seq write (dd)" 1; spin_end ok "$mbps MB/s"; else spin_end skip; fi
  fi

  # латентность через ioping (если есть)
  if have ioping; then
    spin_start "Диск: latency (ioping)"
    # ioping stats: "min/avg/max/mdev = 89.7 us / 121.5 us / ..." — берём 2-й числовой токен (avg)
    local lat; lat="$(ioping -c 20 "$testdir" 2>/dev/null | awk '/min\/avg\/max/{n=0; for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/){n++; if(n==2){print $i; exit}}}')"
    if is_num "$lat" && [ -n "$lat" ]; then metric_add disk ioping_lat_us "$lat" "µs" "ioping seek latency" 0; spin_end ok "${lat} µs"; else spin_end skip; fi
  fi

  rm -rf "$testdir" 2>/dev/null; DISK_TESTDIR=""
}

# ── сеть ─────────────────────────────────────────────────────────────────────
bench_net() {
  cat_enabled net || return 0
  [ "$NET_MODE" = "none" ] && return 0
  section "🌐" "Сеть"

  # латентность всегда (ping)
  net_ping() {
    local host="$1" label="$2"
    spin_start "Ping $label ($host)"
    local out rtt loss jit
    out="$(run_timeout 20 ping -c 10 "$host" 2>/dev/null)"
    # avg rtt: строка "min/avg/max..." (Linux: mdev, macOS: stddev)
    rtt="$(printf '%s' "$out" | awk -F'[ /]+' '/min\/avg\/max/{print $(NF-3); exit} /= [0-9].*\//{n=split($0,a,"/"); print a[5]}' | head -1)"
    [ -z "$rtt" ] && rtt="$(printf '%s' "$out" | sed -n 's/.*= [0-9.]*\/\([0-9.]*\)\/.*/\1/p' | head -1)"
    jit="$(printf '%s' "$out" | sed -n 's/.*\/\([0-9.]*\) ms$/\1/p' | head -1)"
    loss="$(printf '%s' "$out" | sed -n 's/.*[, ]\([0-9][0-9.]*\)% packet loss.*/\1/p' | head -1)"
    if is_num "$rtt" && [ -n "$rtt" ]; then
      metric_add net "ping_${label}_ms" "$rtt" "ms" "Ping $label" 0
      [ -n "$jit" ] && is_num "$jit" && metric_add net "jitter_${label}_ms" "$jit" "ms" "  jitter $label" 0
      [ -n "$loss" ] && is_num "$loss" && metric_add net "loss_${label}_pct" "$loss" "%" "  loss $label" 0
      spin_end ok "${rtt} ms${loss:+, loss ${loss}%}"
    else spin_end skip; fi
  }

  net_ping 1.1.1.1 cloudflare
  net_ping 8.8.8.8 google

  case "$NET_MODE" in
    speedtest)
      if have speedtest; then
        spin_start "Speedtest (Ookla)"
        local out dl ul png
        out="$(run_timeout 90 speedtest --accept-license --accept-gdpr -f json 2>/dev/null)"
        if [ -n "$out" ] && have jq; then
          dl="$(printf '%s' "$out" | jq -r '.download.bandwidth // empty' 2>/dev/null)"  # bytes/s
          ul="$(printf '%s' "$out" | jq -r '.upload.bandwidth // empty' 2>/dev/null)"
          png="$(printf '%s' "$out" | jq -r '.ping.latency // empty' 2>/dev/null)"
          [ -n "$dl" ] && metric_add net down_mbps "$(fdiv "$(fmul "$dl" 8)" 1000000)" "Mbit/s" "Download" 1
          [ -n "$ul" ] && metric_add net up_mbps "$(fdiv "$(fmul "$ul" 8)" 1000000)" "Mbit/s" "Upload" 1
          [ -n "$png" ] && metric_add net idle_latency_ms "$png" "ms" "Latency (idle)" 0
          spin_end ok "$([ -n "$dl" ] && fmt_num "$(fdiv "$(fmul "$dl" 8)" 1000000)" 1) Mbit/s ↓"
        else spin_end skip "нет вывода/jq"; fi
      elif have speedtest-cli; then
        spin_start "Speedtest (speedtest-cli)"
        local out dl ul png
        out="$(run_timeout 90 speedtest-cli --json 2>/dev/null)"
        if [ -n "$out" ] && have jq; then
          dl="$(printf '%s' "$out" | jq -r '.download // empty')"  # bits/s
          ul="$(printf '%s' "$out" | jq -r '.upload // empty')"
          png="$(printf '%s' "$out" | jq -r '.ping // empty')"
          [ -n "$dl" ] && metric_add net down_mbps "$(fdiv "$dl" 1000000)" "Mbit/s" "Download" 1
          [ -n "$ul" ] && metric_add net up_mbps "$(fdiv "$ul" 1000000)" "Mbit/s" "Upload" 1
          [ -n "$png" ] && metric_add net idle_latency_ms "$png" "ms" "Latency (idle)" 0
          spin_end ok "$([ -n "$dl" ] && fmt_num "$(fdiv "$dl" 1000000)" 1) Mbit/s ↓"
        else spin_end skip; fi
      else
        note "speedtest недоступен — измерена только латентность."
      fi
      ;;
    iperf)
      if have iperf3 && [ -n "$IPERF_HOST" ]; then
        spin_start "iperf3 → $IPERF_HOST"
        local out bps
        out="$(run_timeout 30 iperf3 -c "$IPERF_HOST" -J 2>/dev/null)"
        if [ -n "$out" ] && have jq; then
          bps="$(printf '%s' "$out" | jq -r '.end.sum_received.bits_per_second // empty')"
          [ -n "$bps" ] && metric_add net iperf_mbps "$(fdiv "$bps" 1000000)" "Mbit/s" "iperf3 throughput" 1
          spin_end ok
        else spin_end skip; fi
      else
        note "iperf3 или --iperf-host не заданы — пропуск."
      fi
      ;;
  esac
}

# ── приложения (hybrid) ─────────────────────────────────────────────────────────
free_port() {
  local p tries=0
  while [ $tries -lt 50 ]; do
    p=$(( 20000 + (RANDOM % 20000) ))
    # успешный connect => порт занят; возвращаем только тот, куда подключиться НЕ удалось
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then echo "$p"; return 0; fi
    tries=$((tries+1))
  done
  echo $(( 20000 + (RANDOM % 20000) ))
}

wait_port() { # host port tries
  local h="$1" p="$2" n="${3:-50}" i=0
  while [ $i -lt "$n" ]; do
    if (exec 3<>"/dev/tcp/$h/$p") 2>/dev/null; then exec 3>&- 3<&-; return 0; fi
    i=$((i+1)); sleep 0.1
  done
  return 1
}

bench_apps() {
  cat_enabled apps || return 0
  section "🚀" "Приложения (redis / node / nginx / mongodb)"

  bench_redis
  bench_node
  bench_nginx
  bench_mongo
}

bench_redis() {
  if ! have redis-server || ! have redis-benchmark; then note "redis недоступен — пропуск."; return 0; fi
  local port; port="$(free_port)"
  spin_start "redis: запуск + benchmark"
  redis-server --port "$port" --save '' --appendonly no --daemonize no --bind 127.0.0.1 \
    >"$WORKDIR/redis.log" 2>&1 &
  local pid=$!; reg_server "$pid"
  if ! wait_port 127.0.0.1 "$port" 50; then spin_end fail "redis не стартовал"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 0; fi
  local out set get
  # redis-benchmark прогресс печатает через \r (всё в одной строке) — режем на строки.
  # Финальная строка: " SET: 1428571.38 requests per second, p50=0.439 msec"
  out="$(run_timeout 60 redis-benchmark -h 127.0.0.1 -p "$port" -q -n "$REDIS_N" -c 50 -P 16 -t set,get 2>/dev/null | tr '\r' '\n')"
  set="$(printf '%s\n' "$out" | awk '/SET:.*requests per second/{for(i=1;i<=NF;i++) if($i=="SET:"){print $(i+1); exit}}')"
  get="$(printf '%s\n' "$out" | awk '/GET:.*requests per second/{for(i=1;i<=NF;i++) if($i=="GET:"){print $(i+1); exit}}')"
  redis-cli -h 127.0.0.1 -p "$port" shutdown nosave >/dev/null 2>&1 || kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if is_num "$set" && [ -n "$set" ]; then
    metric_add apps redis_set_ops "$set" "ops/s" "Redis SET (pipelined)" 1
    [ -n "$get" ] && is_num "$get" && metric_add apps redis_get_ops "$get" "ops/s" "Redis GET (pipelined)" 1
    spin_end ok "SET $(fmt_int "$set") ops/s"
  else spin_end skip; fi
}

bench_node() {
  if ! have node; then note "node недоступен — пропуск."; return 0; fi

  # 1) CPU-микробенч (crypto+json) — печатает ops/s
  spin_start "node: CPU микробенч"
  local nout
  nout="$(run_timeout 30 node -e '
    const c=require("crypto");
    let t=Date.now(), n=0;
    while(Date.now()-t<3000){ const h=c.createHash("sha256"); h.update("benchx"+n); h.digest("hex"); JSON.parse(JSON.stringify({a:n,b:[1,2,3],c:"x".repeat(64)})); n++; }
    console.log((n/3).toFixed(0));
  ' 2>/dev/null)"
  if is_num "$nout" && [ -n "$nout" ]; then metric_add apps node_ops "$nout" "ops/s" "Node CPU (sha256+JSON)" 1; spin_end ok "$(fmt_int "$nout") ops/s"; else spin_end skip; fi

  # 2) HTTP-нагрузка (если есть wrk): node http server + wrk
  if have wrk; then
    local port; port="$(free_port)"
    local srv="$WORKDIR/server.js"
    cat >"$srv" <<JSSRC
const http=require('http');
const s=http.createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/plain'});res.end('hello');});
s.listen(${port},'127.0.0.1');
JSSRC
    spin_start "node: HTTP throughput (wrk, ${HTTP_DUR}s)"
    node "$srv" >"$WORKDIR/node_http.log" 2>&1 &
    local pid=$!; reg_server "$pid"
    if wait_port 127.0.0.1 "$port" 50; then
      local rps
      rps="$(run_timeout $((HTTP_DUR+10)) wrk -t2 -c50 -d"${HTTP_DUR}s" "http://127.0.0.1:$port/" 2>/dev/null | awk '/Requests\/sec/{print $2; exit}')"
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      if is_num "$rps" && [ -n "$rps" ]; then metric_add apps node_http_rps "$rps" "req/s" "Node HTTP (wrk)" 1; spin_end ok "$(fmt_int "$rps") req/s"; else spin_end skip; fi
    else kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; spin_end skip "сервер не стартовал"; fi
  fi
}

bench_nginx() {
  if ! have nginx; then note "nginx недоступен — пропуск."; return 0; fi
  if ! have wrk; then note "wrk недоступен — nginx HTTP-тест пропущен."; return 0; fi
  local port; port="$(free_port)"
  local root="$WORKDIR/nginx_root"; mkdir -p "$root"
  printf 'hello from nginx benchx\n' >"$root/index.html"
  local conf="$WORKDIR/nginx.conf"
  cat >"$conf" <<NGINX
daemon off;
worker_processes auto;
pid $WORKDIR/nginx.pid;
error_log $WORKDIR/nginx_error.log crit;
events { worker_connections 1024; }
http {
  access_log off;
  sendfile on;
  server {
    listen 127.0.0.1:$port;
    location / { root $root; index index.html; }
  }
}
NGINX
  spin_start "nginx: запуск + HTTP throughput (wrk, ${HTTP_DUR}s)"
  nginx -p "$WORKDIR" -c "$conf" >"$WORKDIR/nginx_start.log" 2>&1 &
  local pid=$!; reg_server "$pid"
  if wait_port 127.0.0.1 "$port" 50; then
    local rps
    rps="$(run_timeout $((HTTP_DUR+10)) wrk -t2 -c100 -d"${HTTP_DUR}s" "http://127.0.0.1:$port/" 2>/dev/null | awk '/Requests\/sec/{print $2; exit}')"
    # корректное завершение nginx
    nginx -p "$WORKDIR" -c "$conf" -s quit >/dev/null 2>&1 || kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    if is_num "$rps" && [ -n "$rps" ]; then metric_add apps nginx_rps "$rps" "req/s" "Nginx static (wrk)" 1; spin_end ok "$(fmt_int "$rps") req/s"; else spin_end skip; fi
  else kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; spin_end skip "nginx не стартовал"; fi
}

bench_mongo() {
  if ! have mongod; then note "mongod недоступен — пропуск (тяжёлая зависимость)."; return 0; fi
  if ! have mongosh && ! have mongo; then note "mongosh/mongo недоступны — mongo-тест пропущен."; return 0; fi
  local shell="mongosh"; have mongosh || shell="mongo"
  local port; port="$(free_port)"
  local dbpath="$WORKDIR/mongo_db"; mkdir -p "$dbpath"
  spin_start "mongodb: запуск + insert/find бенч"
  # mongod запускаем НАПРЯМУЮ (не через run_timeout-функцию), чтобы $! был реальным PID mongod
  mongod --dbpath "$dbpath" --port "$port" --bind_ip 127.0.0.1 \
    --nojournal --wiredTigerCacheSizeGB 1 >"$WORKDIR/mongod.log" 2>&1 &
  local pid=$!; reg_server "$pid"
  if ! wait_port 127.0.0.1 "$port" 80; then
    # повтор без --nojournal (опция удалена в Mongo 7+)
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    mongod --dbpath "$dbpath" --port "$port" --bind_ip 127.0.0.1 >"$WORKDIR/mongod.log" 2>&1 &
    pid=$!; reg_server "$pid"
    if ! wait_port 127.0.0.1 "$port" 80; then spin_end skip "mongod не стартовал"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 0; fi
  fi
  local js="$WORKDIR/mongo_bench.js"
  cat >"$js" <<MJS
const N=${MONGO_INS}, NF=${MONGO_FIND};
const col=db.getSiblingDB("benchx").c;
col.drop();
let t=Date.now();
let batch=[];
for(let i=0;i<N;i++){ batch.push({i:i, v:"x".repeat(64), n:i%1000}); if(batch.length>=1000){ col.insertMany(batch); batch=[]; } }
if(batch.length) col.insertMany(batch);
let ins=(N/((Date.now()-t)/1000));
col.createIndex({n:1});
t=Date.now(); let q=0;
for(let i=0;i<NF;i++){ col.find({n:i%1000}).limit(10).toArray(); q++; }
let fps=(q/((Date.now()-t)/1000));
print("INSERT_OPS="+ins.toFixed(0));
print("FIND_OPS="+fps.toFixed(0));
MJS
  local out ins find
  out="$(run_timeout 90 "$shell" --quiet --port "$port" "$js" 2>/dev/null)"
  ins="$(printf '%s' "$out" | awk -F= '/INSERT_OPS/{print $2; exit}')"
  find="$(printf '%s' "$out" | awk -F= '/FIND_OPS/{print $2; exit}')"
  "$shell" --quiet --port "$port" --eval 'db.getSiblingDB("admin").shutdownServer()' >/dev/null 2>&1 || kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if is_num "$ins" && [ -n "$ins" ]; then
    metric_add apps mongo_insert_ops "$ins" "docs/s" "Mongo insertMany" 1
    [ -n "$find" ] && is_num "$find" && metric_add apps mongo_find_ops "$find" "q/s" "Mongo find (indexed)" 1
    spin_end ok "insert $(fmt_int "$ins") docs/s"
  else spin_end skip; fi
}

# ── дополнительные метрики ───────────────────────────────────────────────────────
bench_extras() {
  cat_enabled extras || return 0
  section "✨" "Дополнительно (syscalls / стабильность под нагрузкой)"

  # syscall / context-switch throughput — важно для event-loop (nginx/node)
  if have sysbench && [ "$SB_MAJOR" = 1 ]; then
    spin_start "Threads/context-switch (sysbench)"
    local ev
    ev="$(sysbench threads --threads="$CPU_THREADS" --thread-yields=1000 --thread-locks=8 --time=8 run 2>/dev/null | awk -F: '/events per second/{gsub(/ /,"",$2);print $2;exit}')"
    if is_num "$ev" && [ -n "$ev" ]; then metric_add extras threads_eps "$ev" "ev/s" "Threads/locks" 1; spin_end ok "$(fmt_int "$ev") ev/s"; else spin_end skip; fi
  fi

  # стабильность под длительной нагрузкой (throttling): burst vs sustained
  if have sysbench; then
    detect_sysbench
    spin_start "Стабильность под нагрузкой (${THERMAL_TIME}s)"
    local burst sustained ratio
    burst="$(sysbench_cpu "$CPU_THREADS" 3)"
    sustained="$(sysbench_cpu "$CPU_THREADS" "$THERMAL_TIME")"
    if is_num "$burst" && is_num "$sustained" && [ -n "$burst" ] && [ -n "$sustained" ]; then
      ratio="$(fdiv "$sustained" "$burst")"
      metric_add extras stability_ratio "$ratio" "x" "Sustained/Burst (1.0=без троттлинга)" 1
      spin_end ok "ratio $(fmt_num "$ratio" 2)"
    else spin_end skip; fi
  fi

  # спавн процессов (актуально для CGI/worker-моделей, форк под нагрузкой)
  spin_start "Спавн процессов (subshell fork)"
  local n=0
  SECONDS=0
  while [ "$SECONDS" -lt 3 ]; do ( : ); n=$((n+1)); done
  local fr; fr="$(fdiv "$n" 3)"
  metric_add extras fork_per_sec "$fr" "proc/s" "Спавн процессов" 1
  spin_end ok "$(fmt_int "$fr") proc/s"
}

# ── workload-индексы (нормированные относительно базовых референсов) ─────────────
# Идея: каждую первичную метрику нормируем к референсу (modern x86 ~ 1000), затем
# взвешиваем по профилю нагрузки. Это даёт сопоставимые между серверами индексы.
get_metric() { # cat key -> value (или пусто)
  local i
  for i in "${!M_CAT[@]}"; do
    if [ "${M_CAT[$i]}" = "$1" ] && [ "${M_KEY[$i]}" = "$2" ]; then printf '%s' "${M_VAL[$i]}"; return 0; fi
  done
  printf ''
}
# нормализованный индекс метрики (higher better): value/ref*1000
idx() { # value ref
  local v="$1" r="$2"
  is_num "$v" && [ -n "$v" ] || { echo ""; return; }
  fmul "$(fdiv "$v" "$r")" 1000
}
# для latency (lower better): ref/value*1000
idx_lat() { local v="$1" r="$2"; is_num "$v" && [ -n "$v" ] || { echo ""; return; }; awk -v v="$v" -v r="$r" 'BEGIN{ if(v<=0){print ""}else{printf "%.6f", r/v*1000} }'; }

# взвешенная сумма компонентов "idx:weight" (отсутствующие передаются как "NA:weight").
# Печатает "score coverage", где coverage = доля собранного веса от полного.
wsum() {
  awk -v s="$1" 'BEGIN{
    n=split(s, parts, " "); sum=0; cw=0; tw=0;
    for(i=1;i<=n;i++){ if(parts[i]=="") continue; split(parts[i], a, ":"); w=a[2]+0; tw+=w;
      if(a[1]!="" && a[1]!="NA"){ sum+=a[1]*w; cw+=w; } }
    if(cw==0 || tw==0){ print "NA 0" } else { printf "%.0f %.2f", sum/cw, cw/tw }
  }'
}
# coverage>=порога?
cov_ok() { awk -v c="$1" -v t="${2:-0.5}" 'BEGIN{exit !(c>=t)}'; }

compute_scores() {
  # референсы (грубые ориентиры современного облачного vCPU)
  local R_SC=1200 R_MC=8000 R_AES=2500 R_MEMBW=12000 R_MEMLAT=90 \
        R_RIOPS=80000 R_WIOPS=40000 \
        R_REDIS=2000000 R_NODEHTTP=40000 R_NGINX=120000 R_NODEOPS=120000 \
        R_MONGOINS=60000 R_MONGOFIND=50000

  local i_sc i_mc i_aes i_membw i_memlat i_riops i_wiops i_redis i_nodehttp i_nginx i_nodeops
  i_sc="$(idx "$(get_metric cpu single_core_eps)" $R_SC)"
  i_mc="$(idx "$(get_metric cpu multi_core_eps)" $R_MC)"
  i_aes="$(idx "$(get_metric cpu aes256_mbs)" $R_AES)"
  # базу полосы берём single-thread (машинно-независимо vs референс), MT — лишь запасной вариант
  i_membw="$(idx "$(get_metric ram read_mibs)" $R_MEMBW)"; [ -z "$i_membw" ] && i_membw="$(idx "$(get_metric ram read_mt_mibs)" $R_MEMBW)"
  i_memlat="$(idx_lat "$(get_metric ram latency_ns)" $R_MEMLAT)"
  i_riops="$(idx "$(get_metric disk randread_iops)" $R_RIOPS)"
  i_wiops="$(idx "$(get_metric disk randwrite_iops)" $R_WIOPS)"
  i_redis="$(idx "$(get_metric apps redis_get_ops)" $R_REDIS)"
  i_nodehttp="$(idx "$(get_metric apps node_http_rps)" $R_NODEHTTP)"
  i_nginx="$(idx "$(get_metric apps nginx_rps)" $R_NGINX)"
  i_nodeops="$(idx "$(get_metric apps node_ops)" $R_NODEOPS)"
  local i_mongoins i_mongofind
  i_mongoins="$(idx "$(get_metric apps mongo_insert_ops)" $R_MONGOINS)"
  i_mongofind="$(idx "$(get_metric apps mongo_find_ops)" $R_MONGOFIND)"

  # каждый workload-индекс собирается из взвешенных компонентов; выводим только
  # если покрыто >=50% веса (иначе индекс из 1-2 метрик ввёл бы в заблуждение).
  local s c
  # mongodb-индекс включает РЕАЛЬНЫЕ mongo-замеры (insert/find), а не только диск/CPU-прокси
  set -- nginx   "${i_sc:-NA}:0.30 ${i_aes:-NA}:0.20 ${i_mc:-NA}:0.20 ${i_membw:-NA}:0.10 ${i_nginx:-NA}:0.20" \
         redis   "${i_sc:-NA}:0.40 ${i_memlat:-NA}:0.25 ${i_membw:-NA}:0.10 ${i_redis:-NA}:0.25" \
         mongodb "${i_riops:-NA}:0.20 ${i_wiops:-NA}:0.15 ${i_mc:-NA}:0.15 ${i_membw:-NA}:0.10 ${i_mongoins:-NA}:0.25 ${i_mongofind:-NA}:0.15" \
         nodejs  "${i_sc:-NA}:0.40 ${i_nodeops:-NA}:0.25 ${i_membw:-NA}:0.15 ${i_nodehttp:-NA}:0.20"

  local NG="" RD="" MG="" ND=""
  while [ $# -ge 2 ]; do
    local name="$1" spec="$2"; shift 2
    # индекс движка показываем ТОЛЬКО если его реальный бенчмарк действительно выполнялся,
    # иначе «MongoDB-индекс» при недоступном mongod вводит в заблуждение
    case "$name" in
      nginx)   [ -n "$(get_metric apps nginx_rps)" ]                              || continue ;;
      redis)   [ -n "$(get_metric apps redis_get_ops)" ]                          || continue ;;
      nodejs)  [ -n "$(get_metric apps node_ops)$(get_metric apps node_http_rps)" ] || continue ;;
      mongodb) [ -n "$(get_metric apps mongo_insert_ops)" ]                        || continue ;;
    esac
    local out; out="$(wsum "$spec")"
    s="${out%% *}"; c="${out##* }"
    [ "$s" = "NA" ] && continue
    cov_ok "$c" 0.5 || continue
    case "$name" in
      nginx)   NG="$s"; score_add nginx   "$s" "Nginx" ;;
      redis)   RD="$s"; score_add redis   "$s" "Redis" ;;
      mongodb) MG="$s"; score_add mongodb "$s" "MongoDB" ;;
      nodejs)  ND="$s"; score_add nodejs  "$s" "Node.js" ;;
    esac
  done

  # общий композит — среднее доступных workload-индексов
  local comp; comp="$(wsum "${NG:-NA}:1 ${RD:-NA}:1 ${MG:-NA}:1 ${ND:-NA}:1")"
  s="${comp%% *}"
  [ "$s" != "NA" ] && score_add overall "$s" "ОБЩИЙ"
}

# ── рендер таблиц ───────────────────────────────────────────────────────────────
render_info() {
  section "🖥" "Система"
  local i
  for i in "${!I_KEY[@]}"; do
    printf '  %s%-16s%s %s\n' "$C_GREY" "${I_KEY[$i]}" "$C_RESET" "${I_VAL[$i]}"
  done
}

render_metrics_table() {
  # печатает таблицу метрик заданной категории
  local cat="$1" title="$2" i any=0
  for i in "${!M_CAT[@]}"; do [ "${M_CAT[$i]}" = "$cat" ] && any=1 && break; done
  [ "$any" = 0 ] && return 0
  printf '\n  %s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
  for i in "${!M_CAT[@]}"; do
    [ "${M_CAT[$i]}" = "$cat" ] || continue
    local val="${M_VAL[$i]}" unit="${M_UNIT[$i]}" label="${M_LABEL[$i]}"
    local disp
    if is_num "$val"; then
      # крупные целые — с разделителями, дробные — 2 знака
      case "$unit" in
        ns|µs|ms|x|%) disp="$(fmt_num "$val" 2)" ;;
        *) disp="$(fmt_int "$val")" ;;
      esac
    else disp="$val"; fi
    printf '  %s%-30s%s %s%14s%s %s%-8s%s\n' "$C_GREY" "$label" "$C_RESET" "$C_BOLD" "$disp" "$C_RESET" "$C_DIM" "$unit" "$C_RESET"
  done
}

render_scores() {
  [ "${#SC_KEY[@]}" = 0 ] && return 0
  section "🏁" "Индексы производительности (выше = быстрее, ~1000 = референс vCPU)"
  # максимум для масштабирования баров
  local maxv=1 i
  for i in "${!SC_VAL[@]}"; do
    awk -v a="${SC_VAL[$i]}" -v m="$maxv" 'BEGIN{exit !(a>m)}' && maxv="${SC_VAL[$i]}"
  done
  local had_proxy=0
  for i in "${!SC_KEY[@]}"; do
    local v="${SC_VAL[$i]}" lbl="${SC_LABEL[$i]}" px="${SC_PROXY[$i]}"
    local mark="  "; [ "$px" = 1 ] && { mark=" ≈"; had_proxy=1; }
    local barlen; barlen="$(awk -v v="$v" -v m="$maxv" 'BEGIN{printf "%d", (m>0? v/m*36 : 0)}')"
    local bar=""; local j=0
    while [ $j -lt "$barlen" ]; do bar="${bar}█"; j=$((j+1)); done
    local col="$C_CYAN"; [ "${SC_KEY[$i]}" = "overall" ] && col="$C_MAGENTA"
    printf '  %s%-12s%s%s %s%-36s%s %s%6s%s\n' "$C_BOLD" "$lbl" "$mark" "$C_RESET" "$col" "$bar" "$C_RESET" "$C_BOLD" "$(fmt_int "$v")" "$C_RESET"
  done
  [ "$had_proxy" = 1 ] && printf '  %s≈ — оценка по синтетике (реальный бенчмарк движка не выполнялся)%s\n' "$C_DIM" "$C_RESET"
}

render_notes() {
  [ "${#NOTES[@]}" = 0 ] && return 0
  printf '\n%s  Заметки:%s\n' "$C_YELLOW" "$C_RESET"
  local n
  for n in "${NOTES[@]}"; do printf '   %s•%s %s\n' "$C_YELLOW" "$C_RESET" "$n"; done
}

render_report() {
  printf '\n'
  hr
  printf '%s%s  BENCHX %s  %s  %s%s\n' "$C_BOLD" "$C_MAGENTA" "$VERSION" "$RUN_TS" "профиль: $PROFILE" "$C_RESET"
  hr
  render_info
  render_metrics_table cpu    "CPU"
  render_metrics_table ram    "RAM"
  render_metrics_table disk   "Диск"
  render_metrics_table net    "Сеть"
  render_metrics_table apps   "Приложения"
  render_metrics_table extras "Дополнительно"
  render_scores
  render_notes
  printf '\n'
}

# ── JSON ────────────────────────────────────────────────────────────────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\f'/\\f}"; s="${s//$'\b'/\\b}"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\016-\037')"   # прочие управляющие байты U+0000-U+001F
  s="${s//	/\\t}"
  printf '%s' "$s"
}
json_val() { # печатает значение: число как есть, иначе в кавычках
  local v="$1"
  if is_num "$v" && [ -n "$v" ]; then printf '%s' "$v"; else printf '"%s"' "$(json_escape "$v")"; fi
}

emit_json() {
  [ -z "$JSON_PATH" ] && return 0
  {
    printf '{\n'
    printf '  "benchx_version": "%s",\n' "$VERSION"
    printf '  "timestamp": "%s",\n' "$RUN_TS"
    printf '  "profile": "%s",\n' "$PROFILE"
    printf '  "os": "%s", "arch": "%s",\n' "$(json_escape "$OS")" "$(json_escape "$ARCH")"

    # system info
    printf '  "system": {\n'
    local i first=1
    for i in "${!I_KEY[@]}"; do
      [ "$first" = 1 ] || printf ',\n'; first=0
      printf '    "%s": "%s"' "$(json_escape "${I_KEY[$i]}")" "$(json_escape "${I_VAL[$i]}")"
    done
    printf '\n  },\n'

    # metrics grouped by category
    printf '  "metrics": {\n'
    local cats="cpu ram disk net apps extras" c cfirst=1
    for c in $cats; do
      local has=0
      for i in "${!M_CAT[@]}"; do [ "${M_CAT[$i]}" = "$c" ] && has=1 && break; done
      [ "$has" = 0 ] && continue
      [ "$cfirst" = 1 ] || printf ',\n'; cfirst=0
      printf '    "%s": {\n' "$c"
      local mfirst=1
      for i in "${!M_CAT[@]}"; do
        [ "${M_CAT[$i]}" = "$c" ] || continue
        [ "$mfirst" = 1 ] || printf ',\n'; mfirst=0
        printf '      "%s": {"value": %s, "unit": "%s", "label": "%s", "higher_is_better": %s}' \
          "$(json_escape "${M_KEY[$i]}")" "$(json_val "${M_VAL[$i]}")" \
          "$(json_escape "${M_UNIT[$i]}")" "$(json_escape "${M_LABEL[$i]}")" "${M_HIGH[$i]}"
      done
      printf '\n    }'
    done
    printf '\n  },\n'

    # scores
    printf '  "scores": {\n'
    local sfirst=1
    for i in "${!SC_KEY[@]}"; do
      [ "$sfirst" = 1 ] || printf ',\n'; sfirst=0
      printf '    "%s": %s' "$(json_escape "${SC_KEY[$i]}")" "$(json_val "${SC_VAL[$i]}")"
    done
    printf '\n  }\n'
    printf '}\n'
  } >"$JSON_PATH"
  printf '%s  JSON-отчёт:%s %s\n' "$C_GREEN" "$C_RESET" "$JSON_PATH"
}

# ── режим сравнения ──────────────────────────────────────────────────────────────
do_compare() {
  [ -r "$COMPARE_A" ] || die "Не найден файл: $COMPARE_A"
  [ -r "$COMPARE_B" ] || die "Не найден файл: $COMPARE_B"
  local engine=""
  if have python3; then engine=py; elif have jq; then engine=jq; else die "Для --compare нужен python3 или jq."; fi

  printf '\n%s%s  Сравнение отчётов%s\n' "$C_BOLD" "$C_MAGENTA" "$C_RESET"
  printf '  A: %s\n  B: %s\n\n' "$COMPARE_A" "$COMPARE_B"

  if [ "$engine" = py ]; then
    A="$COMPARE_A" B="$COMPARE_B" python3 - <<'PY'
import json,os,sys
A=json.load(open(os.environ['A'])); B=json.load(open(os.environ['B']))
def flat(d):
    out={}
    for cat,metrics in d.get('metrics',{}).items():
        for k,v in metrics.items():
            out[f"{cat}.{k}"]=(v.get('value'),v.get('unit',''),v.get('label',k),v.get('higher_is_better',1))
    return out
fa,fb=flat(A),flat(B)
keys=[k for k in fa if k in fb]
G="\033[32m"; R="\033[31m"; Z="\033[0m"; B0="\033[1m"; GR="\033[90m"
print(f"  {B0}{'Метрика':<34}{'A':>14}{'B':>14}{'Δ%':>10}{Z}")
print("  "+"-"*72)
for k in keys:
    va,unit,label,hib=fa[k]; vb=fb[k][0]
    try:
        va=float(va); vb=float(vb)
    except: continue
    if va==0: continue
    diff=(vb-va)/va*100.0
    # для latency меньше=лучше: знак «лучше» инвертируем для цвета
    better = diff>0 if hib else diff<0
    col=G if better else (R if abs(diff)>0.5 else GR)
    arrow="▲" if diff>0 else ("▼" if diff<0 else "=")
    print(f"  {label[:34]:<34}{va:>14.1f}{vb:>14.1f}{col}{diff:>+9.1f}%{Z} {arrow}")
# scores
sa=A.get('scores',{}); sb=B.get('scores',{})
sk=[k for k in sa if k in sb]
if sk:
    print(f"\n  {B0}Индексы{Z}")
    for k in sk:
        try:
            va=float(sa[k]); vb=float(sb[k])
        except: continue
        if va==0: continue
        d=(vb-va)/va*100.0
        col=G if d>=0 else R
        print(f"  {k:<14}{va:>10.0f}{vb:>10.0f}{col}{d:>+9.1f}%{Z}")
PY
  else
    # jq-вариант (упрощённый, без цвета)
    local keys k
    keys="$(jq -r '.metrics | to_entries[] | .key as $c | .value | keys[] | "\($c).\(.)"' "$COMPARE_A" 2>/dev/null)"
    printf '  %-34s %14s %14s %10s\n' "Метрика" "A" "B" "Δ%"
    printf '  %s\n' "------------------------------------------------------------------------"
    for k in $keys; do
      local c="${k%%.*}" m="${k#*.}"
      local va vb lbl hib
      va="$(jq -r ".metrics.\"$c\".\"$m\".value // empty" "$COMPARE_A" 2>/dev/null)"
      vb="$(jq -r ".metrics.\"$c\".\"$m\".value // empty" "$COMPARE_B" 2>/dev/null)"
      lbl="$(jq -r ".metrics.\"$c\".\"$m\".label // \"$m\"" "$COMPARE_A" 2>/dev/null)"
      hib="$(jq -r ".metrics.\"$c\".\"$m\".higher_is_better // 1" "$COMPARE_A" 2>/dev/null)"
      is_num "$va" && is_num "$vb" && [ -n "$va" ] && [ -n "$vb" ] || continue
      awk -v a="$va" 'BEGIN{exit !(a==0)}' && continue   # пропуск нулевой базы (как в python-ветке)
      local d; d="$(awk -v a="$va" -v b="$vb" 'BEGIN{printf "%+.1f",(b-a)/a*100}')"
      local mark; mark="$(awk -v d="$d" -v h="$hib" 'BEGIN{ better=(h+0?d>0:d<0); print (d+0==0?"=":(better?"лучше":"хуже")) }')"
      printf '  %-34s %14s %14s %9s%%  %s\n' "$lbl" "$(fmt_num "$va" 1)" "$(fmt_num "$vb" 1)" "$d" "$mark"
    done
  fi
  printf '\n'
}

# ── очистка ──────────────────────────────────────────────────────────────────────
cleanup() {
  [ -n "$SPIN_PID" ] && { kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; SPIN_PID=""; }
  # подстраховка: гасим серверы и любые фоновые задания (sysbench/fio/сторожа run_timeout)
  local p
  for p in $SERVER_PIDS; do kill "$p" 2>/dev/null; done
  local jp; jp="$(jobs -p 2>/dev/null)"; [ -n "$jp" ] && kill $jp 2>/dev/null
  [ -n "${DISK_TESTDIR:-}" ] && [ -d "$DISK_TESTDIR" ] && rm -rf "$DISK_TESTDIR" 2>/dev/null
  [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ] && rm -rf "$WORKDIR" 2>/dev/null
}

# Ctrl-C / kill: чистимся И ВЫХОДИМ (иначе bash вернётся из обработчика и продолжит прогон)
on_interrupt() {
  trap '' INT TERM            # игнорируем повторные сигналы, пока убираемся
  if [ -n "$SPIN_PID" ]; then kill "$SPIN_PID" 2>/dev/null; printf '\r\033[K'; fi
  printf '\n%s⏹  Прервано — останавливаю бенчмарки и убираюсь...%s\n' "${C_YELLOW:-}" "${C_RESET:-}" >&2
  # групповой сигнал (заберёт даже «внуков» из run_timeout) — ТОЛЬКО если мы лидер своей
  # группы процессов, иначе под `curl|bash`/CI можно прибить родительскую оболочку
  local pgid; pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  if [ -n "$pgid" ] && [ "$pgid" = "$$" ]; then kill -TERM 0 2>/dev/null; fi
  cleanup
  exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

# ── main ─────────────────────────────────────────────────────────────────────────
main() {
  if [ "$MODE" = "compare" ]; then
    do_compare
    exit 0
  fi

  WORKDIR="$(mktemp -d 2>/dev/null || echo "/tmp/benchx.$$")"
  mkdir -p "$WORKDIR" 2>/dev/null

  printf '%s%s  BENCHX %s%s — бенчмарк сервера (%s)\n' "$C_BOLD" "$C_MAGENTA" "$VERSION" "$C_RESET" "$PROFILE"
  printf '  %sОС:%s %s %s   %sПрофиль:%s %s\n\n' "$C_GREY" "$C_RESET" "$OS" "$ARCH" "$C_GREY" "$C_RESET" "$PROFILE"

  detect_pkg
  collect_sysinfo
  detect_sysbench

  section "📦" "Подготовка зависимостей"
  install_deps
  detect_sysbench  # пересчитать после установки

  bench_cpu
  bench_ram
  bench_disk
  bench_net
  bench_apps
  bench_extras

  compute_scores
  render_report
  emit_json
}

main "$@"
