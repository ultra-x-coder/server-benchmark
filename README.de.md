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
**nginx / redis / mongodb / node.js**. Es gibt einen aufgeräumten Terminal-Bericht aus, speichert einen
JSON-Bericht und kann zwei Server vergleichen. **Standardmäßig installiert es nichts** — kein `sudo`, keine
Abfragen; fehlende Werkzeuge werden einfach übersprungen, sodass ein Standardlauf **sicher auf Produktionsservern**
ist. Mit **`--install`** wählen Sie aktiv die Installation fehlender Pakete.

```bash
chmod +x benchx.sh
./benchx.sh            # Standardlauf (~5 Min.)
./benchx.sh --safe     # produktionssicherer Lauf (auf Live-Servern empfohlen)
```

## Auf Produktionsservern ausführen

Verwenden Sie **`--safe`** (vorab mit `--dry-run` ansehen):

```bash
./benchx.sh --safe --dry-run   # zeigt genau, was passieren würde, und beendet sich
./benchx.sh --safe             # sicherer Lauf
./benchx.sh --safe --skip disk # sicherer Lauf ganz ohne Festplattenschreibvorgänge
```

`--safe` garantiert:

- **keine Paketinstallationen, kein `sudo`, keine Dienständerungen** — Ihre `/etc`-Konfigs und laufenden Daemons werden nie angefasst;
- **niedrige CPU/IO-Priorität** (`nice 19` + `ionice -c3`) — die Produktion behält CPU und Festplatte;
- **Netzwerk auf Latenz beschränkt** (nur Ping, keine Bandbreitensättigung);
- **überspringt den Dauerlast-Stresstest**;
- **schreibt nur in ein privates Temp-Verzeichnis** (+ `--json`) und **überschreibt nie vorhandene Dateien**;
- der **Festplattentest prüft zuerst den freien Platz** und verkleinert/überspringt sich, statt die Platte zu füllen.

Diese Schutzmaßnahmen greifen auch außerhalb von `--safe` an den wichtigen Stellen: Das Skript überschreibt keine
vorhandene `--json`-Datei (ohne `--yes`), überschreibt keine vorhandenen Dateien (schreibt nur in eindeutige Temp-Pfade),
prüft vor dem Festplattentest den freien Platz, bindet App-Server an `127.0.0.1` an einem zufälligen hohen Port und
**Ctrl-C stoppt es sofort und räumt auf** (keine verwaisten Server oder zurückgelassenen Temp-Dateien).

## Was gemessen wird

| Kategorie | Metriken | Werkzeuge |
|-----------|----------|-----------|
| **CPU** | Single-Core, Multi-Core, Thread-Skalierung, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | Lese-/Schreibbandbreite (Single- & Multi-Thread), memcpy-Bandbreite, **Latenz bei wahlfreiem Zugriff** (ns) | `sysbench`, `mbw`, zur Laufzeit kompilierter Pointer-Chase |
| **Festplatte** | Typ (NVMe/SSD/HDD), zufällige Lese-/Schreib-IOPS (4k, qd32), sequenzielles Lesen/Schreiben (MB/s), Latenz | `fio` (Fallback: `dd` + `ioping`) |
| **Netzwerk** | Download/Upload (Mbit/s), Leerlauf-Latenz, ping/Jitter/Verlust zu 1.1.1.1 und 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, optional `iperf3` |
| **Apps** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx statisch req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extras** | Kontextwechsel/Threads, Stabilität unter Dauerlast (thermisches Throttling), Prozess-Spawn-Rate | `sysbench`, eingebaut |

### Workload-Indizes

Am Ende berechnet das Skript normalisierte Indizes (≈1000 = eine Referenz-Cloud-vCPU, höher = schneller) für
**nginx / redis / mongodb / node.js** sowie eine Gesamtwertung. Jeder Index ist eine gewichtete Mischung primärer
Metriken (z. B. für redis: Single-Core 40 % + RAM-Latenz 25 % + RAM-Bandbreite 10 % + der echte redis-GET-Benchmark
25 %). Ein Index wird **nur angezeigt, wenn der echte Benchmark der Engine tatsächlich lief** — ist `mongod` nicht
verfügbar, erscheint kein MongoDB-Index. Diese Indizes sind der bequeme Weg, „Wie viel schneller ist Server A als
Server B für redis?“ zu beantworten.

## Verwendung

```bash
./benchx.sh                       # Standard (~5 Min.)
./benchx.sh --quick               # schnell (~1-2 Min.)
./benchx.sh --thorough            # gründlich (~15 Min.)
./benchx.sh --safe                # produktionssicher
./benchx.sh --dry-run             # Plan ausgeben und beenden (keine Änderungen)
./benchx.sh --no-install          # Standardverhalten: nur vorhandene Werkzeuge nutzen (nichts installieren, keine Abfragen)
./benchx.sh --install             # aktiv erlauben, fehlende Pakete zu installieren (warnt zuerst, braucht sudo, fragt vor jedem Paket einzeln nach)
./benchx.sh --install --yes       # alles ohne Einzelabfragen installieren (nicht-interaktiv)
./benchx.sh --net-mode none       # Netzwerktest überspringen
./benchx.sh --json server-a.json  # Bericht speichern
./benchx.sh --only cpu,ram        # nur diese Kategorien
./benchx.sh --skip apps,net       # Kategorien überspringen
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
| `--quick` / `--thorough` | Dauer-Profil (Standard: standard, ~5 Min.) |
| `--safe` | produktionssicher: keine Installationen/sudo/Dienständerungen, niedrige CPU/IO-Priorität, nur Latenz, überspringt Stresstest, überschreibt keine Dateien |
| `--dry-run` | gibt genau aus, was passieren würde, und beendet sich (keine Änderungen, keine Benchmarks) |
| `--no-install` | **Standardverhalten**: nur mit vorhandenen Werkzeugen laufen: nichts installieren, kein sudo, keine Abfragen |
| `--install` | aktiv erlauben, fehlende Pakete zu installieren: zeigt **zuerst eine deutliche Warnung**, fragt **einmal** nach `sudo` und fragt dann **vor jedem Paket einzeln** nach (so wählen Sie, was installiert wird); `--yes` überspringt diese Abfragen und installiert alles |
| `--reinstall` | erzwingt Neuinstallation der benötigten Pakete (repariert auch ein kaputtes dpkg nach Ctrl-C) |
| `--confirm-each` | vor jeder Paket-(Neu-)Installation nachfragen (von `--install` bereits impliziert) |
| `--yes` / `-y` | „ja“ annehmen: keine Abfragen; erlaubt auch das Überschreiben einer vorhandenen `--json`-Datei |
| `--net-mode MODE` | Netzwerktest-Modus: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | Adresse Ihres eigenen iperf3-Servers (setzt `--net-mode iperf`) |
| `--target DIR` | Verzeichnis für den Festplattentest (Standard `.`) |
| `--only CSV` / `--skip CSV` | Kategoriefilter: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | Pfad für den JSON-Bericht |
| `--no-color` | keine Farbe (berücksichtigt auch `NO_COLOR`) |
| `--compare A.json B.json` | zwei Berichte vergleichen und beenden |
| `-h` / `--help` | Hilfe |

## Abhängigkeiten und root

**Standardmäßig installiert das Skript nichts.** Ein einfacher `./benchx.sh`-Lauf installiert keine Pakete, nutzt
kein `sudo` und stellt keine Abfragen; jede Metrik, deren Werkzeug fehlt, wird einfach übersprungen. Das macht einen
Standardlauf sicher für Produktionsserver.

Um tatsächlich fehlende Pakete zu installieren, müssen Sie dies mit **`--install`** aktiv erlauben. In diesem Fall
erkennt das Skript den Paketmanager automatisch (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` unter Linux, `brew` unter
macOS) und installiert das Fehlende.

- Mit `--install` zeigt das Skript **zuerst eine große, deutliche rote Warnung** — eine (Neu-)Installation von Paketen
  kann einen Live-Server beschädigen: `/etc`-Konfigs überschreiben, Dienste wie redis/nginx/mongodb neu starten oder
  stören und verhaltensändernde Upgrades einspielen. Auf einem interaktiven Terminal fragt es danach nach Bestätigung,
  bevor irgendetwas geschieht.
- Mit `--install` fragt das Skript **vor jedem Paket einzeln** nach, bevor es installiert wird, sodass Sie auswählen
  können, welche Pakete Sie installieren und welche Sie überspringen (dasselbe Verhalten wie `--confirm-each`, das von
  `--install` nun impliziert wird). Mit zusätzlichem `--yes` entfallen diese Einzelabfragen und alles wird installiert
  (für nicht-interaktive Läufe).
- Unter Linux benötigt die Installation von Systempaketen **root** — mit `--install` fragt das Skript **einmal** nach der Erlaubnis für `sudo`.
- Ohne `--install` (das Standardverhalten, ebenso bei `--no-install`/`--safe`) wird nur verwendet, was bereits
  vorhanden ist; der Rest wird sauber übersprungen und vermerkt.
- Unter macOS benötigt `brew` kein root.
- `--reinstall` repariert einen kaputten `dpkg`-Zustand (z. B. nach einem abgebrochenen `apt`) und installiert Pakete neu.
  Es zeigt **zuerst eine deutliche Warnung** — eine Neuinstallation kann angepasste `/etc`-Konfigs überschreiben und Dienste
  neu starten; sie löscht keine Daten, aber auf einem Produktionsserver sind `--no-install`/`--safe` vorzuziehen.

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
  Hinweis: `--safe` läuft mit niedriger Priorität, daher spiegeln die Werte freie Kapazität statt Spitzendurchsatz wider.
- Der Festplattentest schreibt eine eindeutige temporäre Datei in `--target` (standardmäßig das aktuelle Verzeichnis) und entfernt sie.
- Speedtest kontaktiert externe Ookla-Server; falls unerwünscht, `--net-mode latency` oder `--net-mode none` verwenden.
- App-Benchmarks starten Dienste auf `127.0.0.1` an einem zufälligen hohen Port und fahren sie nach Abschluss herunter.

## Lizenz

MIT
