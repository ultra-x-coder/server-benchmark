# benchx — Server-Performance-Benchmark (Linux / macOS)

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

[English](README.md) · [简体中文](README.zh.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **Deutsch** · [Italiano](README.it.md) · [Español](README.es.md)

Ein einzelnes Bash-Skript, das CPU, RAM, Festplatte und Netzwerk misst — sowie die reale Performance von
**nginx / redis / mongodb / node.js**. Es installiert seine Abhängigkeiten selbst, gibt einen aufgeräumten
Terminal-Bericht aus, speichert einen JSON-Bericht und kann zwei Server/Läufe vergleichen.

```bash
./benchx.sh                 # Standardlauf (~5 Min.)
```

## Was gemessen wird

| Kategorie | Metriken | Werkzeuge |
|-----------|----------|-----------|
| **CPU** | Single-Core, Multi-Core, Thread-Skalierung, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | Lese-/Schreibbandbreite (Single- & Multi-Thread), memcpy-Bandbreite, **Latenz bei wahlfreiem Zugriff** (ns) | `sysbench`, `mbw`, zur Laufzeit kompilierter Pointer-Chase |
| **Festplatte** | Typ (NVMe/SSD/HDD), zufällige Lese-/Schreib-IOPS (4k, qd32), sequenzielles Lesen/Schreiben (MB/s), Latenz (Ø) | `fio` (Fallback: `dd` + `ioping`) |
| **Netzwerk** | Download/Upload (Mbit/s), Leerlauf-Latenz, ping/Jitter/Verlust zu 1.1.1.1 und 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, optional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx statisch req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | Kontextwechsel/Threads, **Stabilität unter Dauerlast** (thermisches Throttling), Prozess-Spawn-Rate | `sysbench`, eingebaut |

### Workload-Indizes

Am Ende berechnet das Skript normalisierte Indizes (≈1000 = eine Referenz-Cloud-vCPU, höher = schneller) für
**nginx / redis / mongodb / node.js** sowie eine Gesamtwertung. Jeder Index ist eine gewichtete Mischung primärer
Metriken (z. B. für redis: Single-Core 40 % + RAM-Latenz 25 % + RAM-Bandbreite 10 % + der echte redis-GET-Benchmark
25 %). Ein Index wird nur angezeigt, wenn ≥50 % seines Gewichts erfasst wurden (damit er nie in die Irre führt).
Diese Indizes sind der bequeme Weg, die Frage „Wie viel schneller ist Server A als Server B für redis?“ zu
beantworten. Eine `≈`-Markierung bedeutet, dass der Index nur aus synthetischen Metriken geschätzt wurde
(der echte Engine-Benchmark lief nicht).

## Verwendung

```bash
chmod +x benchx.sh
./benchx.sh                       # Standard (~5 Min.)
./benchx.sh --quick               # schnell (~1-2 Min.)
./benchx.sh --thorough            # gründlich (~15 Min.)
./benchx.sh --json server-a.json  # Bericht speichern
./benchx.sh --no-net              # Netzwerktest überspringen
./benchx.sh --only cpu,ram        # nur diese Kategorien
./benchx.sh --skip apps,net       # Kategorien überspringen
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # eigenen iperf3-Server statt speedtest verwenden
```

### Zwei Server vergleichen

```bash
# auf Server A:
./benchx.sh --json a.json
# auf Server B:
./benchx.sh --json b.json
# überall:
./benchx.sh --compare a.json b.json
```

Gibt eine Tabelle mit Metriken und Indizes samt prozentualer Differenz aus (grün = B ist schneller, rot = langsamer).

## Optionen

| Flag | Zweck |
|------|-------|
| `--quick` / `--standard` / `--thorough` | Dauer-Profil |
| `--no-net` | Netzwerktest überspringen |
| `--net-mode speedtest\|latency\|iperf\|none` | Modus des Netzwerktests |
| `--iperf-host HOST` | Adresse Ihres eigenen iperf3-Servers |
| `--target DIR` | Verzeichnis für den Festplattentest (Standard `.`) |
| `--no-install` | nichts installieren, nur vorhandene Werkzeuge nutzen |
| `--yes` | sudo-Abfrage automatisch mit „ja“ beantworten |
| `--json PATH` | Pfad für den JSON-Bericht |
| `--only CSV` / `--skip CSV` | Kategoriefilter: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | keine Farbe (berücksichtigt auch `NO_COLOR`) |
| `--compare A.json B.json` | zwei Berichte vergleichen |

## Abhängigkeiten und root

Das Skript erkennt den Paketmanager automatisch (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` unter Linux,
`brew` unter macOS) und installiert das Fehlende.

- Unter Linux benötigt die Installation von Systempaketen **root** — das Skript fragt **einmal** nach der Erlaubnis für `sudo`.
- Wenn Sie ablehnen, wird nur installiert, was **ohne root** verfügbar ist (z. B. `speedtest-cli` via `pip --user`);
  alles andere wird sauber übersprungen und im Abschnitt „Hinweise“ vermerkt.
- Unter macOS benötigt `brew` kein root.
- `--no-install` deaktiviert die Installation vollständig.

Jede nicht verfügbare Metrik wird einfach übersprungen (✓ erledigt, ∅ übersprungen, ✗ Fehler) — das Skript stürzt nie ab.

## Voraussetzungen

- `bash` (kompatibel mit 3.2 — dem macOS-Standard) und Standard-Utilities.
- `--compare` benötigt `python3` **oder** `jq`.
- Die RAM-Latenz benötigt einen C-Compiler (`cc`/`gcc`/`clang`) — sonst wird diese Metrik übersprungen.

## JSON-Bericht

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

## Hinweise zur Genauigkeit

- Auf einer im Leerlauf befindlichen Maschine ausführen; bei „lauten Nachbarn“ (Virtualisierung) schwanken die Ergebnisse — `--thorough` verwenden.
- Der Festplattentest schreibt eine temporäre Datei in `--target` (standardmäßig das aktuelle Verzeichnis) und entfernt sie.
- Speedtest kontaktiert externe Ookla-Server; falls unerwünscht, `--net-mode iperf` oder `--no-net` verwenden.
- App-Benchmarks starten Dienste auf `127.0.0.1` an einem zufälligen hohen Port und fahren sie nach Abschluss herunter.

## Lizenz

MIT
