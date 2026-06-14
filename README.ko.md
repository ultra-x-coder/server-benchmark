# benchx — 서버 성능 벤치마크 (Linux / macOS)

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

[English](README.md) · [简体中文](README.zh.md) · [Русский](README.ru.md) · **한국어** · [日本語](README.ja.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Español](README.es.md)

CPU, RAM, 디스크, 네트워크는 물론 **nginx / redis / mongodb / node.js** 의 실제 성능까지 측정하는 단일 bash 스크립트입니다.
**기본적으로는 아무것도 설치하지 않으며**(설치·sudo·질문 없이 도구가 없는 지표는 그냥 생략), 깔끔한 터미널 리포트를 출력하고, JSON 리포트를 저장하며, 두 서버를 비교할 수 있습니다.
기본 실행은 **운영 서버에서도 안전**합니다. 누락된 패키지를 설치하려면 `--install` 로 명시적으로 활성화해야 합니다.

```bash
chmod +x benchx.sh
./benchx.sh            # 표준 실행 (~5분)
./benchx.sh --safe     # 운영 안전 실행 (라이브 서버에서 권장)
```

## 운영 서버에서 실행

**`--safe`** 를 사용하세요 (먼저 `--dry-run` 으로 미리 확인):

```bash
./benchx.sh --safe --dry-run   # 무엇이 일어날지 보여주고 종료
./benchx.sh --safe             # 안전 실행
./benchx.sh --safe --skip disk # 디스크 쓰기 전혀 없이 안전 실행
```

`--safe` 가 보장하는 것:

- **패키지 설치 없음, `sudo` 없음, 서비스 변경 없음** —— `/etc` 설정과 실행 중인 데몬을 절대 건드리지 않음;
- **낮은 CPU/IO 우선순위**(`nice 19` + `ionice -c3`) —— 운영 프로세스가 CPU와 디스크를 우선 차지;
- **네트워크는 지연만 측정**(ping 만, 대역폭 포화 없음);
- **지속 부하 스트레스 테스트 생략**;
- **개인 임시 디렉터리에만 기록**(+ `--json`), 기존 파일을 **절대 덮어쓰지 않음**;
- **디스크 테스트는 먼저 여유 공간을 확인**하고, 디스크를 채우는 대신 크기를 줄이거나 생략.

이 보호들은 `--safe` 가 아니어도 중요한 곳에서 동작합니다: 스크립트는 기존 `--json` 을 덮어쓰지 않으며(`--yes` 없이는),
어떤 기존 파일도 덮어쓰지 않고(고유 임시 경로에만 기록), 디스크 테스트 전 공간을 확인하고, 앱 서버를 `127.0.0.1` 의
임의의 높은 포트에 바인딩하며, **Ctrl-C 시 즉시 중단하고 정리합니다**(고아 서버나 남은 임시 파일 없음).

## 측정 항목

| 분류 | 지표 | 도구 |
|------|------|------|
| **CPU** | 싱글코어, 멀티코어, 스레드 확장성, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | 읽기/쓰기 대역폭 (싱글·멀티스레드), memcpy 대역폭, **랜덤 액세스 지연** (ns) | `sysbench`, `mbw`, 즉석 컴파일 포인터 체이스 |
| **디스크** | 종류 (NVMe/SSD/HDD), 랜덤 읽기/쓰기 IOPS (4k, qd32), 순차 읽기/쓰기 (MB/s), 지연 | `fio` (대체: `dd` + `ioping`) |
| **네트워크** | 다운로드/업로드 (Mbit/s), 유휴 지연, 1.1.1.1 및 8.8.8.8 에 대한 ping/지터/손실 | Ookla `speedtest` / `speedtest-cli`, `ping`, 선택적 `iperf3` |
| **앱** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx 정적 req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **추가** | 컨텍스트 스위치/스레드, 지속 부하 안정성(열 스로틀링), 프로세스 생성 속도 | `sysbench`, 내장 명령 |

### 워크로드 인덱스

스크립트는 마지막에 **nginx / redis / mongodb / node.js** 및 종합 점수에 대해 정규화된 인덱스
(≈1000 = 기준 클라우드 vCPU, 높을수록 빠름)를 계산합니다. 각 인덱스는 주요 지표의 가중 조합입니다
(예: redis 의 경우 싱글코어 40% + RAM 지연 25% + RAM 대역폭 10% + 실제 redis GET 벤치마크 25%).
인덱스는 **해당 엔진의 실제 벤치마크가 실제로 실행된 경우에만** 표시됩니다 —— `mongod` 가 없으면 MongoDB 인덱스는
나타나지 않습니다. 이 인덱스들은 "서버 A 가 redis 에서 서버 B 보다 얼마나 빠른가"에 답하기 좋은 지표입니다.

## 사용법

```bash
./benchx.sh                       # 표준 (~5분)
./benchx.sh --quick               # 빠름 (~1-2분)
./benchx.sh --thorough            # 정밀 (~15분)
./benchx.sh --safe                # 운영 안전
./benchx.sh --dry-run             # 계획을 출력하고 종료 (아무것도 변경하지 않음)
./benchx.sh --no-install          # 이미 있는 도구만 사용 (기본 동작: 설치·질문 없음)
./benchx.sh --install             # 누락된 패키지 설치 허용 (각 패키지마다 질문, 경고 표시 + sudo 필요)
./benchx.sh --install --yes       # 패키지별 질문 없이 모두 설치 (비대화형)
./benchx.sh --net-mode none       # 네트워크 테스트 생략
./benchx.sh --json server-a.json  # 리포트 저장
./benchx.sh --only cpu,ram        # 해당 분류만
./benchx.sh --skip apps,net       # 분류 생략
```

### 두 서버 비교

```bash
# 서버 A 에서:
./benchx.sh --json a.json
# 서버 B 에서:
./benchx.sh --json b.json
# 어디서나:
./benchx.sh --compare a.json b.json
```

지표와 인덱스를 백분율 차이와 함께 표로 출력합니다 (초록 = B 가 더 빠름, 빨강 = 더 느림).

## 옵션

| 플래그 | 용도 |
|--------|------|
| `--quick` / `--thorough` | 실행 시간 프로파일 (기본 standard, ~5분) |
| `--safe` | 운영 안전: 설치/sudo/서비스 변경 없음, 낮은 CPU/IO 우선순위, 지연만 측정, 스트레스 테스트 생략, 파일 비덮어쓰기 |
| `--dry-run` | 무엇이 일어날지 출력하고 종료 (변경·벤치마크 없음) |
| `--no-install` | **기본 동작**: 이미 있는 도구만으로 실행, 아무것도 설치하지 않음 (설치·sudo·질문 없음) |
| `--install` | 누락된 패키지 설치를 허용하는 옵트인: 먼저 눈에 띄는 경고를 표시하고 `sudo` 로 root 권한을 요청. **각 패키지를 설치하기 전에 개별적으로 질문하므로 무엇을 설치할지 직접 고를 수 있음**(`--confirm-each` 와 동일한 동작을 이미 포함); `--yes` 를 함께 쓰면 이 패키지별 질문 없이 모두 설치 |
| `--reinstall` | 필요한 패키지 강제 재설치 (Ctrl-C 후 손상된 dpkg 도 복구) |
| `--confirm-each` | 각 패키지 설치/재설치 전에 질문 (`--install` 은 이미 이 동작을 포함함) |
| `--yes` / `-y` | "예" 가정: 질문 없음; 기존 `--json` 파일 덮어쓰기도 허용 |
| `--net-mode MODE` | 네트워크 테스트 모드: `speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | 자체 iperf3 서버 주소 (`--net-mode iperf` 설정) |
| `--target DIR` | 디스크 테스트 디렉터리 (기본값 `.`) |
| `--only CSV` / `--skip CSV` | 분류 필터: `cpu,ram,disk,net,apps,extras` |
| `--json PATH` | JSON 리포트 경로 |
| `--no-color` | 색상 없음 (`NO_COLOR` 도 따름) |
| `--compare A.json B.json` | 두 리포트 비교 후 종료 |
| `-h` / `--help` | 도움말 |

## 의존성과 root

**기본적으로 스크립트는 아무것도 설치하지 않습니다** —— sudo 도 쓰지 않고, 질문도 하지 않으며, 도구가 없는 지표는 그냥 생략합니다. 그래서 기본 실행은 운영 서버에서도 안전합니다.

> **TIP:** `--install` 없이 실행하면(운영 안전 기본값인 no-install 모드) 스크립트는 출력 상단 근처에 안내용 TIP 배너를 표시합니다. 이 배너는 현재 no-install 모드로 실행 중이라 일부 지표가 생략될 수 있음을 알려줍니다 —— 도구가 없으면 깨끗한 서버에서는 redis / nodejs / nginx / mongodb 같은 앱 지표와 speedtest 를 측정하지 못할 수 있습니다. `--install` 로 다시 실행하면 누락된 도구를 설치하고 **전체** 결과를 수집합니다(먼저 경고를 표시하며 `sudo` 가 필요합니다). 여기에 `-y` 를 더하면 패키지별 질문 없이 모두 설치합니다: `./benchx.sh --install -y`. 이 배너는 `--install` 또는 `--safe` 사용 시에는 표시되지 않습니다.

- 누락된 패키지를 실제로 설치하려면 **`--install`** 로 명시적으로 활성화해야 합니다. 이 경우 스크립트는 패키지 관리자(Linux 의 `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`, macOS 의 `brew`)를 자동 감지합니다.
- `--install` 사용 시 스크립트는 **먼저 크고 눈에 띄는 빨간 경고**를 표시합니다 —— 패키지 (재)설치는 라이브 서버를 망가뜨릴 수 있습니다(`/etc` 설정 덮어쓰기, redis/nginx/mongodb 같은 서비스 재시작·중단, 동작이 바뀌는 업그레이드 적용). 이어서 대화형 터미널에서 실행을 진행하기 전에 확인을 묻습니다.
- `--install` 은 **각 패키지를 설치하기 전에 개별적으로 질문**하므로, 어떤 패키지를 설치하고 어떤 것을 건너뛸지 직접 선택할 수 있습니다(`--confirm-each` 와 동일한 동작을 이미 포함합니다). 패키지별 질문 없이 모두 설치하려면(비대화형 실행) `--yes` 를 함께 사용하세요.
- Linux 에서 시스템 패키지 설치에는 **root** 가 필요합니다 —— `--install` 사용 시 스크립트는 `sudo` 사용 허가를 **한 번만** 묻습니다.
- `--no-install`(기본 동작) 또는 `--safe` 에서는 **root 없이** 사용 가능한 것만 쓰고 나머지는 우아하게 생략·기록합니다.
  공식 **Ookla `speedtest` CLI 는 tarball 에서 root 없이** 설치됩니다(`~/.local/bin` 에).
- macOS 에서 `brew` 는 root 가 필요 없습니다.
- `--reinstall` 은 손상된 `dpkg` 상태(예: 중단된 `apt` 이후)를 복구하고 패키지를 강제 재설치합니다(설치 동작을 활성화하므로 `--install` 처럼 취급됩니다).
  먼저 **눈에 띄는 경고**를 표시합니다 —— 재설치는 사용자 정의 `/etc` 설정을 덮어쓰고 서비스를 재시작할 수 있습니다.
  데이터를 삭제하지는 않지만, 운영 서버에서는 `--no-install`/`--safe` 를 권장합니다.

사용할 수 없는 지표는 그냥 생략됩니다 (✓ 완료, ∅ 생략, ✗ 오류) —— 스크립트는 절대 죽지 않습니다.

## 요구 사항

- `bash` (3.2 호환 —— macOS 기본값) 및 표준 유틸리티.
- `--compare` 에는 `python3` **또는** `jq` 가 필요합니다.
- RAM 지연에는 C 컴파일러(`cc`/`gcc`/`clang`)가 필요합니다 —— 없으면 해당 지표는 생략됩니다.

## JSON 리포트

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

## 정확도 참고

- 유휴 상태의 머신에서 실행하세요. "시끄러운 이웃"(가상화) 환경에서는 결과가 흔들립니다 —— `--thorough` 를 사용하세요.
  참고: `--safe` 는 낮은 우선순위로 실행되므로 그 수치는 최대 처리량이 아니라 여유 용량을 반영합니다.
- 디스크 테스트는 `--target`(기본값은 현재 디렉터리)에 고유한 임시 파일을 쓰고 이후 삭제합니다.
- Speedtest 는 외부 Ookla 서버에 접속합니다. 원치 않으면 `--net-mode latency` 또는 `--net-mode none` 을 사용하세요.
- 앱 벤치마크는 `127.0.0.1` 의 임의의 높은 포트에서 서비스를 시작하고 완료 후 종료합니다.

## 라이선스

MIT
