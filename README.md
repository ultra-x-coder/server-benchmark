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
**nginx / redis / mongodb / node.js**. It installs its own dependencies, prints a clean terminal report,
saves a JSON report, and can compare two servers/runs.

```bash
./benchx.sh                 # standard run (~5 min)
```

## What it measures

| Category | Metrics | Tools |
|----------|---------|-------|
| **CPU** | single-core, multi-core, thread scaling, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | read/write bandwidth (single- & multi-threaded), memcpy bandwidth, **random-access latency** (ns) | `sysbench`, `mbw`, compiled pointer-chase |
| **Disk** | type (NVMe/SSD/HDD), random read/write IOPS (4k, qd32), sequential read/write (MB/s), latency (avg) | `fio` (fallback: `dd` + `ioping`) |
| **Network** | download / upload (Mbit/s), idle latency, ping/jitter/loss to 1.1.1.1 and 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, optional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx static req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | context-switch/threads, **sustained-load stability** (thermal throttling), process-spawn rate | `sysbench`, builtins |

### Workload indexes

At the end, the script computes normalized indexes (≈1000 = a reference cloud vCPU, higher = faster) for
**nginx / redis / mongodb / node.js** plus an overall score. Each index is a weighted blend of primary metrics
(e.g. for redis: single-core 40% + RAM latency 25% + RAM bandwidth 10% + the real redis GET benchmark 25%).
An index is shown only when ≥50% of its weight was collected (so it never misleads). These indexes are the
convenient way to answer "how much faster is server A than server B for redis". A `≈` marker means the index
is an estimate from synthetic metrics only (the real engine benchmark did not run).

## Usage

```bash
chmod +x benchx.sh
./benchx.sh                       # standard (~5 min)
./benchx.sh --quick               # fast (~1-2 min)
./benchx.sh --thorough            # thorough (~15 min)
./benchx.sh --json server-a.json  # save report
./benchx.sh --no-net              # skip network test
./benchx.sh --only cpu,ram        # only these categories
./benchx.sh --skip apps,net       # skip categories
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # use your own iperf3 server instead of speedtest
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

This prints a table of metrics and indexes with the percentage difference (green = B is faster, red = slower).

## Options

| Flag | Purpose |
|------|---------|
| `--quick` / `--standard` / `--thorough` | duration profile |
| `--no-net` | skip the network test |
| `--net-mode speedtest\|latency\|iperf\|none` | network test mode |
| `--iperf-host HOST` | address of your own iperf3 server |
| `--target DIR` | directory for the disk test (default `.`) |
| `--no-install` | do not install anything, use only the tools already present |
| `--yes` | assume "yes" to the sudo prompt |
| `--json PATH` | path for the JSON report |
| `--only CSV` / `--skip CSV` | category filter: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | no color (also honors `NO_COLOR`) |
| `--compare A.json B.json` | compare two reports |

## Dependencies and root

The script auto-detects your package manager (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` on Linux, `brew` on macOS)
and installs what is missing.

- On Linux, installing system packages needs **root** — the script asks **once** for permission to use `sudo`.
- If you decline, only what is available **without root** is installed (e.g. `speedtest-cli` via `pip --user`);
  everything else is skipped gracefully and noted in the "Notes" section.
- On macOS, `brew` does not need root.
- `--no-install` disables installation entirely.

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
- The disk test writes a temporary file into `--target` (the current directory by default) and removes it.
- Speedtest contacts external Ookla servers; use `--net-mode iperf` or `--no-net` if that is undesirable.
- App benchmarks start services on `127.0.0.1` on a random high port and shut them down when finished.

## License

MIT
