# benchx — benchmark de rendimiento de servidores (Linux / macOS)

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

[English](README.md) · [简体中文](README.zh.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · **Español**

Un único script de bash que mide CPU, RAM, disco y red, además del rendimiento real de
**nginx / redis / mongodb / node.js**. Instala sus propias dependencias, imprime un informe limpio en la
terminal, guarda un informe JSON y puede comparar dos servidores/ejecuciones.

```bash
./benchx.sh                 # ejecución estándar (~5 min)
```

## Qué mide

| Categoría | Métricas | Herramientas |
|-----------|----------|--------------|
| **CPU** | un núcleo, varios núcleos, escalado por hilos, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | ancho de banda de lectura/escritura (un hilo y múltiples hilos), ancho de banda memcpy, **latencia de acceso aleatorio** (ns) | `sysbench`, `mbw`, pointer-chase compilado al vuelo |
| **Disco** | tipo (NVMe/SSD/HDD), IOPS de lectura/escritura aleatorias (4k, qd32), lectura/escritura secuencial (MB/s), latencia (media) | `fio` (alternativa: `dd` + `ioping`) |
| **Red** | descarga/subida (Mbit/s), latencia en reposo, ping/jitter/pérdida hacia 1.1.1.1 y 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, opcional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx estático req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | cambio de contexto/hilos, **estabilidad bajo carga sostenida** (throttling térmico), tasa de creación de procesos | `sysbench`, integrados |

### Índices de carga de trabajo

Al final, el script calcula índices normalizados (≈1000 = una vCPU de nube de referencia, más alto = más rápido)
para **nginx / redis / mongodb / node.js** más una puntuación global. Cada índice es una mezcla ponderada de
métricas primarias (p. ej., para redis: un núcleo 40% + latencia de RAM 25% + ancho de banda de RAM 10% + el
benchmark real de redis GET 25%). Un índice solo se muestra cuando se ha recopilado ≥50% de su peso (para que nunca
induzca a error). Estos índices son la forma cómoda de responder «cuánto más rápido es el servidor A que el servidor B
para redis». Una marca `≈` significa que el índice es una estimación basada solo en métricas sintéticas
(el benchmark real del motor no se ejecutó).

## Uso

```bash
chmod +x benchx.sh
./benchx.sh                       # estándar (~5 min)
./benchx.sh --quick               # rápido (~1-2 min)
./benchx.sh --thorough            # exhaustivo (~15 min)
./benchx.sh --json server-a.json  # guardar informe
./benchx.sh --no-net              # omitir la prueba de red
./benchx.sh --only cpu,ram        # solo estas categorías
./benchx.sh --skip apps,net       # omitir categorías
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # usar tu propio servidor iperf3 en lugar de speedtest
```

### Comparar dos servidores

```bash
# en el servidor A:
./benchx.sh --json a.json
# en el servidor B:
./benchx.sh --json b.json
# en cualquier lugar:
./benchx.sh --compare a.json b.json
```

Imprime una tabla de métricas e índices con la diferencia porcentual (verde = B es más rápido, rojo = más lento).

## Opciones

| Indicador | Propósito |
|-----------|-----------|
| `--quick` / `--standard` / `--thorough` | perfil de duración |
| `--no-net` | omitir la prueba de red |
| `--net-mode speedtest\|latency\|iperf\|none` | modo de la prueba de red |
| `--iperf-host HOST` | dirección de tu propio servidor iperf3 |
| `--target DIR` | directorio para la prueba de disco (por defecto `.`) |
| `--no-install` | no instalar nada, usar solo las herramientas ya presentes |
| `--yes` | responder «sí» automáticamente al aviso de sudo |
| `--json PATH` | ruta para el informe JSON |
| `--only CSV` / `--skip CSV` | filtro de categorías: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | sin color (también respeta `NO_COLOR`) |
| `--compare A.json B.json` | comparar dos informes |

## Dependencias y root

El script detecta automáticamente el gestor de paquetes (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` en Linux,
`brew` en macOS) e instala lo que falta.

- En Linux, instalar paquetes del sistema requiere **root** — el script pide permiso para usar `sudo` **una sola vez**.
- Si lo rechazas, solo se instala lo que está disponible **sin root** (p. ej., `speedtest-cli` mediante `pip --user`);
  todo lo demás se omite con elegancia y se anota en la sección «Notas».
- En macOS, `brew` no necesita root.
- `--no-install` desactiva por completo la instalación.

Cualquier métrica no disponible simplemente se omite (✓ hecho, ∅ omitido, ✗ error) — el script nunca se bloquea.

## Requisitos

- `bash` (compatible con 3.2 — el predeterminado de macOS) y utilidades estándar.
- `--compare` necesita `python3` **o** `jq`.
- La latencia de RAM necesita un compilador de C (`cc`/`gcc`/`clang`) — de lo contrario esa métrica se omite.

## Informe JSON

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

## Notas sobre la precisión

- Ejecútalo en una máquina inactiva; con «vecinos ruidosos» (virtualización) los resultados varían — usa `--thorough`.
- La prueba de disco escribe un archivo temporal en `--target` (el directorio actual por defecto) y lo elimina.
- Speedtest contacta servidores externos de Ookla; si no es deseable, usa `--net-mode iperf` o `--no-net`.
- Los benchmarks de apps inician servicios en `127.0.0.1` en un puerto alto aleatorio y los detienen al terminar.

## Licencia

MIT
