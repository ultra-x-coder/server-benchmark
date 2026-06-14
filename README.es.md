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
**nginx / redis / mongodb / node.js**. Por defecto **no instala nada**: una ejecución estándar no usa `sudo`,
no hace preguntas y simplemente omite cualquier métrica cuya herramienta falte, por lo que es **seguro de
ejecutar en servidores de producción**. Usa `--install` para optar por instalar los paquetes que falten. Imprime
un informe limpio en la terminal, guarda un informe JSON y puede comparar dos servidores.

```bash
chmod +x benchx.sh
./benchx.sh            # ejecución estándar (~5 min)
./benchx.sh --safe     # ejecución segura para producción (recomendada en servidores en vivo)
```

## Ejecución en servidores de producción

Usa **`--safe`** (previsualiza antes con `--dry-run`):

```bash
./benchx.sh --safe --dry-run   # muestra exactamente qué ocurriría y sale
./benchx.sh --safe             # ejecución segura
./benchx.sh --safe --skip disk # ejecución segura sin ninguna escritura en disco
```

`--safe` garantiza:

- **sin instalación de paquetes, sin `sudo`, sin cambios en servicios** — tus configuraciones en `/etc` y los daemons en ejecución nunca se tocan;
- **baja prioridad de CPU/IO** (`nice 19` + `ionice -c3`) — la producción conserva la CPU y el disco;
- **red limitada a la latencia** (solo ping, sin saturar el ancho de banda);
- **omite la prueba de estrés a plena carga sostenida**;
- **escribe solo en un directorio temporal privado** (+ `--json`) y **nunca sobrescribe archivos existentes**;
- la **prueba de disco comprueba primero el espacio libre** y se reduce/omite en lugar de llenar el disco.

Estas protecciones también actúan fuera de `--safe` donde importa: el script no sobrescribe un archivo `--json`
existente (sin `--yes`), no sobrescribe ningún archivo existente (solo escribe en rutas temporales únicas),
comprueba el espacio libre antes de la prueba de disco, vincula los servidores de apps a `127.0.0.1` en un puerto
alto aleatorio y **Ctrl-C lo detiene de inmediato y limpia** (sin servidores huérfanos ni archivos temporales residuales).

## Qué mide

| Categoría | Métricas | Herramientas |
|-----------|----------|--------------|
| **CPU** | un núcleo, varios núcleos, escalado por hilos, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | ancho de banda de lectura/escritura (un hilo y múltiples hilos), ancho de banda memcpy, **latencia de acceso aleatorio** (ns) | `sysbench`, `mbw`, pointer-chase compilado al vuelo |
| **Disco** | tipo (NVMe/SSD/HDD), IOPS de lectura/escritura aleatorias (4k, qd32), lectura/escritura secuencial (MB/s), latencia | `fio` (alternativa: `dd` + `ioping`) |
| **Red** | descarga/subida (Mbit/s), latencia en reposo, ping/jitter/pérdida hacia 1.1.1.1 y 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, opcional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx estático req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | cambio de contexto/hilos, estabilidad bajo carga sostenida (throttling térmico), tasa de creación de procesos | `sysbench`, integrados |

### Índices de carga de trabajo

Al final, el script calcula índices normalizados (≈1000 = una vCPU de nube de referencia, más alto = más rápido)
para **nginx / redis / mongodb / node.js** más una puntuación global. Cada índice es una mezcla ponderada de
métricas primarias (p. ej., para redis: un núcleo 40% + latencia de RAM 25% + ancho de banda de RAM 10% + el
benchmark real de redis GET 25%). Un índice se muestra **solo si el benchmark real del motor se ejecutó realmente** —
si `mongod` no está disponible, no aparece ningún índice de MongoDB. Estos índices son la forma cómoda de responder
«cuánto más rápido es el servidor A que el servidor B para redis».

## Uso

```bash
./benchx.sh                       # estándar (~5 min)
./benchx.sh --quick               # rápido (~1-2 min)
./benchx.sh --thorough            # exhaustivo (~15 min)
./benchx.sh --safe                # seguro para producción
./benchx.sh --dry-run             # imprime el plan y sale (sin cambios)
./benchx.sh --install             # opta por instalar los paquetes que falten (pregunta por cada paquete; avisa primero, pide sudo)
./benchx.sh --install --yes       # instala todo sin preguntar por cada paquete (no interactivo)
./benchx.sh --no-install          # comportamiento por defecto: usa solo las herramientas ya presentes (sin instalar, sin preguntas)
./benchx.sh --net-mode none       # omite la prueba de red
./benchx.sh --json server-a.json  # guarda el informe
./benchx.sh --only cpu,ram        # solo estas categorías
./benchx.sh --skip apps,net       # omite categorías
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
| `--quick` / `--thorough` | perfil de duración (por defecto standard, ~5 min) |
| `--safe` | seguro para producción: sin instalaciones/sudo/cambios de servicios, baja prioridad de CPU/IO, solo latencia, omite la prueba de estrés, no sobrescribe archivos |
| `--dry-run` | imprime exactamente qué ocurriría y sale (sin cambios, sin benchmarks) |
| `--install` | opta por instalar los paquetes que falten: pregunta por **cada paquete individualmente** (para que elijas qué instalar y omitas el resto); primero muestra un aviso prominente de que (re)instalar puede dañar un servidor en vivo y pide `sudo` (una sola vez). Añade `--yes` para omitir esas preguntas e instalar todo |
| `--no-install` | **comportamiento por defecto**: ejecuta solo con las herramientas ya presentes: sin instalar, sin sudo, sin preguntas |
| `--reinstall` | reinstala a la fuerza los paquetes requeridos (también repara un dpkg roto tras un Ctrl-C) |
| `--confirm-each` | pregunta antes de instalar/reinstalar cada paquete (`--install` ya lo implica) |
| `--yes` / `-y` | asume «sí»: sin preguntas; también permite sobrescribir un archivo `--json` existente |
| `--net-mode MODE` | modo de la prueba de red: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | dirección de tu propio servidor iperf3 (establece `--net-mode iperf`) |
| `--target DIR` | directorio para la prueba de disco (por defecto `.`) |
| `--only CSV` / `--skip CSV` | filtro de categorías: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | ruta para el informe JSON |
| `--no-color` | sin color (también respeta `NO_COLOR`) |
| `--compare A.json B.json` | compara dos informes y sale |
| `-h` / `--help` | ayuda |

## Dependencias y root

Por defecto el script **no instala nada**: una ejecución estándar no usa `sudo`, no hace preguntas y simplemente
omite cualquier métrica cuya herramienta falte. Esto hace que la ejecución por defecto sea segura en servidores de
producción.

Para instalar realmente los paquetes que falten debes optar explícitamente con **`--install`**. El script detecta
automáticamente el gestor de paquetes (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` en Linux, `brew` en macOS) e instala
lo que falta.

> **TIP:** Cuando se ejecuta **sin `--install`** (el comportamiento por defecto, seguro para producción, modo no-install),
> el script imprime un aviso informativo cerca del inicio de su salida que recuerda que se está ejecutando en modo
> no-install, por lo que **algunas métricas pueden omitirse**. Si faltan herramientas, métricas de apps como
> `redis` / `nodejs` / `nginx` / `mongodb` y la prueba de speedtest pueden no estar disponibles en un servidor recién
> instalado. Vuelve a ejecutarlo con **`--install`** para instalar las herramientas que falten y recopilar el conjunto
> **completo** de resultados (avisa primero; requiere `sudo`); añade **`-y`** para instalar todo sin preguntar por cada
> paquete: `./benchx.sh --install -y`. El aviso **no aparece** cuando se usa `--install` o `--safe`.

- Con `--install`, el script muestra **primero un aviso prominente** de que (re)instalar paquetes puede dañar un
  servidor en vivo (sobrescribir configuraciones en `/etc`, reiniciar o interrumpir servicios como redis/nginx/mongodb,
  arrastrar actualizaciones que cambian el comportamiento) y, en una terminal interactiva, **pide confirmación antes de
  hacer nada**. Luego **pregunta por cada paquete individualmente** antes de instalarlo (lo mismo que hace
  `--confirm-each`), de modo que puedes elegir qué instalar y omitir el resto. Añade **`--yes`** junto a `--install`
  para instalar todo sin esas preguntas por paquete (ejecuciones no interactivas).
- En Linux, instalar paquetes del sistema requiere **root** — con `--install` el script pide permiso para usar `sudo`
  **una sola vez**.
- Por defecto (o con `--no-install`/`--safe`), solo se usa lo que ya está presente; todo lo demás se omite con elegancia
  y se anota.
- En macOS, `brew` no necesita root.
- `--reinstall` repara un estado `dpkg` roto (p. ej., tras un `apt` interrumpido) y reinstala los paquetes.
  Muestra **primero un aviso prominente** — reinstalar puede sobrescribir configuraciones personalizadas en `/etc` y
  reiniciar servicios; no elimina tus datos, pero en un servidor de producción es preferible `--no-install`/`--safe`.

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
  Nota: `--safe` se ejecuta con baja prioridad, por lo que sus números reflejan la capacidad libre, no el pico.
- La prueba de disco escribe un archivo temporal único en `--target` (el directorio actual por defecto) y lo elimina.
- Speedtest contacta servidores externos de Ookla; si no es deseable, usa `--net-mode latency` o `--net-mode none`.
- Los benchmarks de apps inician servicios en `127.0.0.1` en un puerto alto aleatorio y los detienen al terminar.

## Licencia

MIT
