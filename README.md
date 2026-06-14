# benchx — server performance benchmark (Linux / macOS)

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

**English** · [简体中文](README.zh.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Español](README.es.md)

A single bash script that measures CPU, RAM, disk, and network, plus the real-world performance of
**nginx / redis / mongodb / node.js**. By default it **installs nothing** — it uses no `sudo`, asks no
prompts, and simply skips any metric whose tool is missing, so a plain run is **safe on production servers**.
Pass **`--install`** to opt in to installing missing packages. It prints a clean terminal report,
saves a JSON report, and can compare two servers.

```bash
chmod +x benchx.sh
./benchx.sh            # standard run (~5 min)
./benchx.sh --safe     # production-safe run (recommended on live servers)
```

## Running on production servers

Use **`--safe`** (preview first with `--dry-run`):

```bash
./benchx.sh --safe --dry-run   # show exactly what would happen, then exit
./benchx.sh --safe             # safe run
./benchx.sh --safe --skip disk # safe run with zero disk writes
```

`--safe` guarantees:

- **no package installs, no `sudo`, no service changes** — your `/etc` configs and running daemons are never touched;
- **low CPU/IO priority** (`nice 19` + `ionice -c3`) — production keeps the CPU and disk;
- **network limited to latency** (ping only, no bandwidth saturation);
- **skips the sustained full-load stress test**;
- **writes only to a private temp dir** (+ `--json`) and **never overwrites existing files**;
- the **disk test checks free space first** and shrinks or skips itself instead of filling the disk.

These safeguards are also active outside `--safe` where it matters: the script never overwrites an existing
`--json` file (without `--yes`), never overwrites existing files (it writes to unique temp paths only), checks
disk free space before the disk test, binds app servers to `127.0.0.1` on a random high port, and **Ctrl-C stops
it immediately and cleans up** (no orphaned servers or leftover temp files).

## What it measures

| Category | Metrics | Tools |
|----------|---------|-------|
| **CPU** | single-core, multi-core, thread scaling, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | read/write bandwidth (single- & multi-threaded), memcpy bandwidth, **random-access latency** (ns) | `sysbench`, `mbw`, compiled pointer-chase |
| **Disk** | type (NVMe/SSD/HDD), random read/write IOPS (4k, qd32), sequential read/write (MB/s), latency | `fio` (fallback: `dd` + `ioping`) |
| **Network** | download / upload (Mbit/s), idle latency, ping/jitter/loss to 1.1.1.1 and 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, optional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx static req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | context-switch/threads, sustained-load stability (thermal throttling), process-spawn rate | `sysbench`, builtins |

### Workload indexes

At the end the script computes normalized indexes (≈1000 = a reference cloud vCPU, higher = faster) for
**nginx / redis / mongodb / node.js** plus an overall score. Each index is a weighted blend of primary metrics
(e.g. for redis: single-core 40% + RAM latency 25% + RAM bandwidth 10% + the real redis GET benchmark 25%).
An index is shown **only when the engine's real benchmark actually ran** — if `mongod` is unavailable, no
MongoDB index appears. These indexes are the convenient way to answer "how much faster is server A than server B
for redis".

## Usage

```bash
./benchx.sh                       # standard (~5 min)
./benchx.sh --quick               # fast (~1-2 min)
./benchx.sh --thorough            # thorough (~15 min)
./benchx.sh --safe                # production-safe
./benchx.sh --dry-run             # print the plan and exit (no changes, no benchmarks)
./benchx.sh --install             # opt in to installing missing packages (warns first, needs sudo, asks about each package)
./benchx.sh --install --yes       # install everything without per-package prompts (non-interactive)
./benchx.sh --no-install          # default: use only tools already present (install nothing, no prompts)
./benchx.sh --net-mode none       # skip the network test
./benchx.sh --json server-a.json  # save report
./benchx.sh --only cpu,ram        # only these categories
./benchx.sh --skip apps,net       # skip categories
```

### Comparing two servers

```bash
# on server A:
./benchx.sh --json a.json
# on server B:
./benchx.sh --json b.json
# anywhere:
./benchx.sh --compare a.json b.json
```

Prints a table of metrics and indexes with the percentage difference (green = B is faster, red = slower).

## Options

| Flag | Purpose |
|------|---------|
| `--quick` / `--thorough` | duration profile (default: standard, ~5 min) |
| `--safe` | production-safe: no installs/sudo/service changes, low CPU/IO priority, latency-only network, skips the stress test, never overwrites files |
| `--dry-run` | print exactly what would happen, then exit (no changes, no benchmarks) |
| `--install` | opt in to installing missing packages: prints a prominent warning first, asks for `sudo`, then asks about **each package individually** so you can choose what to install (use `--yes` to skip those prompts) |
| `--no-install` | **default**: run with whatever tools are already present — install nothing, no sudo, no prompts |
| `--reinstall` | force-reinstall required packages (also repairs a broken dpkg after a Ctrl-C); requires `--install` |
| `--confirm-each` | prompt before installing/reinstalling each package (`--install` already implies this) |
| `--yes` / `-y` | assume "yes": no prompts; also allows overwriting an existing `--json` file |
| `--net-mode MODE` | network test mode: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | address of your own iperf3 server (sets `--net-mode iperf`) |
| `--target DIR` | directory for the disk test (default: `.`) |
| `--only CSV` / `--skip CSV` | category filter: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | path for the JSON report |
| `--no-color` | no color (also honors `NO_COLOR`) |
| `--compare A.json B.json` | compare two reports and exit |
| `-h` / `--help` | help |

## Dependencies and root

**By default the script installs nothing.** A plain `./benchx.sh` run uses no `sudo`, asks no prompts, and
simply skips any metric whose tool is missing — this makes a default run safe on production servers. This is
exactly what `--no-install`/`--safe` document.

- To actually install missing packages, pass **`--install`**. It auto-detects your package manager
  (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` on Linux, `brew` on macOS) and installs what is missing.
- `--install` first prints a **big, prominent warning** that package (re)installs can break a live server —
  they can overwrite customized `/etc` configs, restart or disrupt services (redis/nginx/mongodb), and pull in
  behaviour-changing upgrades. It then asks about **each package individually**, so you can choose which ones
  to install and skip the rest. Pass **`--yes`** alongside **`--install`** to skip these per-package prompts and
  install everything (handy for non-interactive runs).
- On Linux, installing system packages needs **root** — `--install` asks **once** for permission to use `sudo`.
- On macOS, `brew` does not need root.
- `--reinstall` (requires `--install`) repairs a broken `dpkg` state (e.g. after an interrupted `apt`) and
  force-reinstalls packages, with the same prominent warning first. It does not delete your data, but on a
  production server prefer the default (`--no-install`/`--safe`).

Any unavailable metric is simply skipped (✓ done, ∅ skipped, ✗ error) — the script never crashes.

## Requirements

- `bash` (compatible with 3.2 — the macOS default) and standard utilities.
- `--compare` needs `python3` **or** `jq`.
- RAM latency needs a C compiler (`cc`/`gcc`/`clang`) — otherwise that metric is skipped.

## JSON report

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

## Accuracy notes

- Run it on an idle machine; on noisy neighbors (virtualization) results vary — use `--thorough`.
  Note that `--safe` runs at low priority, so its numbers reflect spare capacity rather than peak throughput.
- The disk test writes a unique temporary file into `--target` (the current directory by default) and removes it.
- Speedtest contacts external Ookla servers; use `--net-mode latency` or `--net-mode none` if that is undesirable.
- App benchmarks start services on `127.0.0.1` on a random high port and shut them down when finished.

## License

MIT
