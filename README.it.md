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
**nginx / redis / mongodb / node.js**. Stampa un report pulito nel terminale, salva un report JSON e può
confrontare due server. Per impostazione predefinita **non installa nulla**: un'esecuzione standard non usa
`sudo`, non pone domande e salta semplicemente le metriche i cui strumenti mancano, risultando così
**sicura da eseguire su server di produzione**. Usa `--install` per acconsentire all'installazione dei pacchetti mancanti.

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
./benchx.sh --install             # acconsenti a installare i pacchetti mancanti (chiede per ogni pacchetto, avvisa prima, richiede sudo)
./benchx.sh --install --yes       # installa tutto senza chiedere per ogni pacchetto (non interattivo)
./benchx.sh --no-install          # comportamento predefinito: usa solo gli strumenti già presenti (niente installazioni, niente domande)
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
| `--install` | acconsenti a installare i pacchetti mancanti: chiede `sudo` (una volta) ma **prima** mostra un avviso ben visibile sul rischio per i server live, poi **chiede su ogni singolo pacchetto** (così puoi scegliere cosa installare e saltare il resto); aggiungi `--yes` per installare tutto senza queste domande |
| `--no-install` | **comportamento predefinito**: esegui solo con gli strumenti già presenti: niente installazioni, sudo o domande |
| `--reinstall` | reinstalla forzatamente i pacchetti richiesti (ripara anche un dpkg rotto dopo un Ctrl-C) |
| `--confirm-each` | chiede prima di installare/reinstallare ogni pacchetto (`--install` lo implica già) |
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

Per impostazione predefinita lo script **non installa nulla**: usa solo gli strumenti già presenti, senza `sudo`
e senza porre domande, e salta con eleganza ogni metrica il cui strumento manca (questo è il comportamento di
`--no-install`/`--safe`). La **CLI ufficiale Ookla `speedtest` viene installata senza root dal suo tarball** (in `~/.local/bin`).

Quando lo script viene eseguito **senza `--install`** (la modalità no-install, predefinita e sicura per la produzione),
stampa vicino all'inizio dell'output un **banner informativo TIP**. Il banner spiega che:

- è in esecuzione in modalità no-install, quindi alcune metriche potrebbero essere saltate;
- gli strumenti mancanti significano che le metriche delle app come **redis / nodejs / nginx / mongodb** e lo **speedtest** possono non essere disponibili su un server spoglio;
- rieseguire con **`--install`** installa gli strumenti mancanti e raccoglie l'**insieme completo** dei risultati (con avviso preventivo; richiede `sudo`);
- aggiungere **`-y`** installa tutto senza una domanda per ogni pacchetto: `./benchx.sh --install -y`.

Il banner **non** appare quando si usa `--install` o `--safe`.

Per installare davvero i pacchetti mancanti devi acconsentire con **`--install`**. In tal caso lo script rileva
automaticamente il gestore di pacchetti (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk` su Linux, `brew` su macOS) e:

- Su Linux l'installazione dei pacchetti di sistema richiede **root** — lo script chiede **una sola volta** il permesso di usare `sudo`.
- **prima** stampa un avviso ben visibile in rosso: la (re)installazione di pacchetti può compromettere un server live
  — sovrascrivere config in `/etc`, riavviare o interrompere servizi (redis/nginx/mongodb), introdurre aggiornamenti
  che cambiano il comportamento.
- chiede **conferma** su un terminale interattivo prima di fare qualsiasi cosa.
- poi **chiede su ogni singolo pacchetto** prima di installarlo, così puoi scegliere quali pacchetti installare e saltare il resto; aggiungi **`--yes`** per installare tutto senza queste domande (esecuzioni non interattive).
- Su macOS `brew` non richiede root.
- `--reinstall` ripara uno stato `dpkg` rotto (ad es. dopo un `apt` interrotto) e reinstalla i pacchetti.
  Mostra **prima un avviso ben visibile** — la reinstallazione può sovrascrivere config personalizzate in `/etc` e
  riavviare servizi; non elimina i tuoi dati, ma su un server di produzione attieniti al comportamento predefinito (`--no-install`/`--safe`).

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
