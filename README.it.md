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
terminale, salva un report JSON e può confrontare due server. È progettato per essere **sicuro da eseguire su server di produzione**.

```bash
chmod +x benchx.sh
./benchx.sh            # esecuzione standard (~5 min)
./benchx.sh --safe     # esecuzione sicura per la produzione (consigliata sui server live)
```

## Esecuzione su server di produzione

Usa **`--safe`** (anteprima prima con `--dry-run`):

```bash
./benchx.sh --safe --dry-run   # mostra esattamente cosa accadrebbe, poi esce
./benchx.sh --safe             # esecuzione sicura
./benchx.sh --safe --skip disk # esecuzione sicura senza alcuna scrittura su disco
```

`--safe` garantisce:

- **nessuna installazione di pacchetti, nessun `sudo`, nessuna modifica ai servizi** — le tue configurazioni in `/etc` e i daemon in esecuzione non vengono mai toccati;
- **bassa priorità CPU/IO** (`nice 19` + `ionice -c3`) — la produzione mantiene CPU e disco;
- **rete limitata alla latenza** (solo ping, nessuna saturazione di banda);
- **salta lo stress test a carico pieno prolungato**;
- **scrive solo in una directory temporanea privata** (+ `--json`) e **non sovrascrive mai file esistenti**;
- il **test del disco controlla prima lo spazio libero** e si riduce/salta invece di riempire il disco.

Queste protezioni sono attive anche fuori da `--safe` dove conta: lo script non sovrascrive un file `--json`
esistente (senza `--yes`), non sovrascrive alcun file esistente (scrive solo su percorsi temporanei univoci),
controlla lo spazio libero prima del test del disco, lega i server delle app a `127.0.0.1` su una porta alta
casuale e **Ctrl-C lo ferma immediatamente e ripulisce** (nessun server orfano né file temporanei residui).

## Cosa misura

| Categoria | Metriche | Strumenti |
|-----------|----------|-----------|
| **CPU** | single-core, multi-core, scalabilità sui thread, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | banda in lettura/scrittura (singolo e multi-thread), banda memcpy, **latenza ad accesso casuale** (ns) | `sysbench`, `mbw`, pointer-chase compilato al volo |
| **Disco** | tipo (NVMe/SSD/HDD), IOPS lettura/scrittura casuali (4k, qd32), lettura/scrittura sequenziale (MB/s), latenza | `fio` (fallback: `dd` + `ioping`) |
| **Rete** | download/upload (Mbit/s), latenza a riposo, ping/jitter/perdita verso 1.1.1.1 e 8.8.8.8 | Ookla `speedtest` / `speedtest-cli`, `ping`, opzionale `iperf3` |
| **App** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx statico req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **Extra** | cambio di contesto/thread, stabilità sotto carico prolungato (throttling termico), tasso di spawn dei processi | `sysbench`, integrati |

### Indici di carico di lavoro

Alla fine lo script calcola indici normalizzati (≈1000 = una vCPU cloud di riferimento, più alto = più veloce) per
**nginx / redis / mongodb / node.js** più un punteggio complessivo. Ogni indice è una combinazione pesata di
metriche primarie (ad es. per redis: single-core 40% + latenza RAM 25% + banda RAM 10% + il benchmark reale
redis GET 25%). Un indice viene mostrato **solo se il benchmark reale del motore è stato effettivamente eseguito** —
se `mongod` non è disponibile, non appare alcun indice MongoDB. Questi indici sono il modo comodo per rispondere a
«quanto è più veloce il server A rispetto al server B per redis».

## Utilizzo

```bash
./benchx.sh                       # standard (~5 min)
./benchx.sh --quick               # veloce (~1-2 min)
./benchx.sh --thorough            # approfondito (~15 min)
./benchx.sh --safe                # sicuro per la produzione
./benchx.sh --dry-run             # stampa il piano ed esce (nessuna modifica)
./benchx.sh --no-install          # usa solo gli strumenti già presenti (niente installazioni, niente domande)
./benchx.sh --net-mode none       # salta il test di rete
./benchx.sh --json server-a.json  # salva il report
./benchx.sh --only cpu,ram        # solo queste categorie
./benchx.sh --skip apps,net       # salta le categorie
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
| `--quick` / `--thorough` | profilo di durata (predefinito standard, ~5 min) |
| `--safe` | sicuro per la produzione: niente installazioni/sudo/modifiche ai servizi, bassa priorità CPU/IO, solo latenza, salta lo stress test, non sovrascrive file |
| `--dry-run` | stampa esattamente cosa accadrebbe, poi esce (nessuna modifica, nessun benchmark) |
| `--no-install` | esegui solo con gli strumenti già presenti: niente installazioni, sudo o domande |
| `--reinstall` | reinstalla forzatamente i pacchetti richiesti (ripara anche un dpkg rotto dopo un Ctrl-C) |
| `--confirm-each` | chiede prima di installare/reinstallare ogni pacchetto |
| `--yes` / `-y` | assume «sì»: nessuna domanda; consente anche di sovrascrivere un file `--json` esistente |
| `--net-mode MODE` | modalità del test di rete: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | indirizzo del tuo server iperf3 (imposta `--net-mode iperf`) |
| `--target DIR` | directory per il test del disco (predefinita `.`) |
| `--only CSV` / `--skip CSV` | filtro categorie: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | percorso del report JSON |
| `--no-color` | nessun colore (rispetta anche `NO_COLOR`) |
| `--compare A.json B.json` | confronta due report ed esce |
| `-h` / `--help` | aiuto |

## Dipendenze e root

Lo script rileva automaticamente il gestore di pacchetti (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` su Linux,
`brew` su macOS) e installa ciò che manca.

- Su Linux l'installazione dei pacchetti di sistema richiede **root** — lo script chiede **una sola volta** il permesso di usare `sudo`.
- Se rifiuti (o con `--no-install`/`--safe`), viene usato solo ciò che è disponibile **senza root**; tutto il resto
  viene saltato con eleganza e annotato. La **CLI ufficiale Ookla `speedtest` viene installata senza root dal suo tarball** (in `~/.local/bin`).
- Su macOS `brew` non richiede root.
- `--reinstall` ripara uno stato `dpkg` rotto (ad es. dopo un `apt` interrotto) e reinstalla i pacchetti.
  Mostra **prima un avviso ben visibile** — la reinstallazione può sovrascrivere config personalizzate in `/etc` e
  riavviare servizi; non elimina i tuoi dati, ma su un server di produzione preferisci `--no-install`/`--safe`.

Qualsiasi metrica non disponibile viene semplicemente saltata (✓ fatto, ∅ saltato, ✗ errore) — lo script non va mai in crash.

## Requisiti

- `bash` (compatibile con 3.2 — il predefinito di macOS) e le utility standard.
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
  Nota: `--safe` viene eseguito a bassa priorità, quindi i suoi numeri riflettono la capacità libera, non il picco.
- Il test del disco scrive un file temporaneo univoco in `--target` (per impostazione predefinita la directory corrente) e lo rimuove.
- Speedtest contatta server Ookla esterni; se non è desiderato, usa `--net-mode latency` o `--net-mode none`.
- I benchmark delle app avviano servizi su `127.0.0.1` su una porta alta casuale e li arrestano al termine.

## Licenza

MIT
