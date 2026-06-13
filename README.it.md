# benchx — benchmark delle prestazioni del server (Linux / macOS)

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

[English](README.md) · [简体中文](README.zh.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Deutsch](README.de.md) · **Italiano** · [Español](README.es.md)

Un singolo script bash che misura CPU, RAM, disco e rete, oltre alle prestazioni reali di
**nginx / redis / mongodb / node.js**. Installa da sé le proprie dipendenze, stampa un report pulito nel
terminale, salva un report JSON e può confrontare due server/esecuzioni.

```bash
./benchx.sh                 # esecuzione standard (~5 min)
```

## Cosa misura

| Categoria | Metriche | Strumenti |
|-----------|----------|-----------|
| **CPU** | single-core, multi-core, scalabilità sui thread, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | banda in lettura/scrittura (singolo e multi-thread), banda memcpy, **latenza ad accesso casuale** (ns) | `sysbench`, `mbw`, pointer-chase compilato al volo |
| **Disco** | tipo (NVMe/SSD/HDD), IOPS lettura/scrittura casuali (4k, qd32), lettura/scrittura sequenziale (MB/s), latenza (media) | `fio` (fallback: `dd` + `ioping`) |
| **Rete** | download/upload (Mbit/s), latenza a riposo, ping/jitter/perdita verso 1.1.1.1 e 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, opzionale `iperf3` |
| **App** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx statico req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extra** | cambio di contesto/thread, **stabilità sotto carico prolungato** (throttling termico), tasso di spawn dei processi | `sysbench`, integrati |

### Indici di carico di lavoro

Alla fine lo script calcola indici normalizzati (≈1000 = una vCPU cloud di riferimento, più alto = più veloce) per
**nginx / redis / mongodb / node.js** più un punteggio complessivo. Ogni indice è una combinazione pesata di
metriche primarie (ad es. per redis: single-core 40% + latenza RAM 25% + banda RAM 10% + il benchmark reale
redis GET 25%). Un indice viene mostrato solo quando è stato raccolto ≥50% del suo peso (così non trae mai in
inganno). Questi indici sono il modo comodo per rispondere a «quanto è più veloce il server A rispetto al server B
per redis». Un contrassegno `≈` significa che l'indice è una stima basata solo su metriche sintetiche
(il benchmark reale del motore non è stato eseguito).

## Utilizzo

```bash
chmod +x benchx.sh
./benchx.sh                       # standard (~5 min)
./benchx.sh --quick               # veloce (~1-2 min)
./benchx.sh --thorough            # approfondito (~15 min)
./benchx.sh --json server-a.json  # salva il report
./benchx.sh --no-net              # salta il test di rete
./benchx.sh --only cpu,ram        # solo queste categorie
./benchx.sh --skip apps,net       # salta le categorie
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # usa il tuo server iperf3 invece di speedtest
```

### Confrontare due server

```bash
# sul server A:
./benchx.sh --json a.json
# sul server B:
./benchx.sh --json b.json
# ovunque:
./benchx.sh --compare a.json b.json
```

Stampa una tabella di metriche e indici con la differenza percentuale (verde = B è più veloce, rosso = più lento).

## Opzioni

| Flag | Scopo |
|------|-------|
| `--quick` / `--standard` / `--thorough` | profilo di durata |
| `--no-net` | salta il test di rete |
| `--net-mode speedtest\|latency\|iperf\|none` | modalità del test di rete |
| `--iperf-host HOST` | indirizzo del tuo server iperf3 |
| `--target DIR` | directory per il test del disco (predefinita `.`) |
| `--no-install` | non installare nulla, usa solo gli strumenti già presenti |
| `--yes` | rispondi automaticamente «sì» al prompt sudo |
| `--json PATH` | percorso del report JSON |
| `--only CSV` / `--skip CSV` | filtro categorie: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | nessun colore (rispetta anche `NO_COLOR`) |
| `--compare A.json B.json` | confronta due report |

## Dipendenze e root

Lo script rileva automaticamente il gestore di pacchetti (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` su Linux,
`brew` su macOS) e installa ciò che manca.

- Su Linux l'installazione dei pacchetti di sistema richiede **root** — lo script chiede **una sola volta** il permesso di usare `sudo`.
- Se rifiuti, viene installato solo ciò che è disponibile **senza root** (ad es. `speedtest-cli` tramite `pip --user`);
  tutto il resto viene saltato con eleganza e annotato nella sezione «Note».
- Su macOS `brew` non richiede root.
- `--no-install` disabilita completamente l'installazione.

Qualsiasi metrica non disponibile viene semplicemente saltata (✓ fatto, ∅ saltato, ✗ errore) — lo script non va mai in crash.

## Requisiti

- `bash` (compatibile con 3.2 — il valore predefinito di macOS) e le utility standard.
- `--compare` richiede `python3` **oppure** `jq`.
- La latenza della RAM richiede un compilatore C (`cc`/`gcc`/`clang`) — altrimenti quella metrica viene saltata.

## Report JSON

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

## Note sulla precisione

- Esegui su una macchina inattiva; con «vicini rumorosi» (virtualizzazione) i risultati variano — usa `--thorough`.
- Il test del disco scrive un file temporaneo in `--target` (per impostazione predefinita la directory corrente) e lo rimuove.
- Speedtest contatta server Ookla esterni; se non è desiderato, usa `--net-mode iperf` o `--no-net`.
- I benchmark delle app avviano servizi su `127.0.0.1` su una porta alta casuale e li arrestano al termine.

## Licenza

MIT
