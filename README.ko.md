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

CPU, RAM, 디스크, 네트워크는 물론 **nginx / redis / mongodb / node.js** 의 실제 성능까지 측정하는
단일 bash 스크립트입니다. 의존성을 스스로 설치하고, 깔끔한 터미널 리포트를 출력하며,
JSON 리포트를 저장하고, 두 서버/두 실행 결과를 비교할 수 있습니다.

```bash
./benchx.sh                 # 표준 실행 (~5분)
```

## 측정 항목

| 분류 | 지표 | 도구 |
|------|------|------|
| **CPU** | 싱글코어, 멀티코어, 스레드 확장성, AES-256 (TLS), SHA-256 | `sysbench`, `openssl` |
| **RAM** | 읽기/쓰기 대역폭 (싱글·멀티스레드), memcpy 대역폭, **랜덤 액세스 지연** (ns) | `sysbench`, `mbw`, 즉석 컴파일 포인터 체이스 |
| **디스크** | 종류 (NVMe/SSD/HDD), 랜덤 읽기/쓰기 IOPS (4k, qd32), 순차 읽기/쓰기 (MB/s), 지연 (평균) | `fio` (대체: `dd` + `ioping`) |
| **네트워크** | 다운로드/업로드 (Mbit/s), 유휴 지연, 1.1.1.1 및 8.8.8.8 에 대한 ping/지터/손실 | Ookla `speedtest` / `speedtest-cli`, `ping`, 선택적 `iperf3` |
| **앱** | Redis SET/GET ops/s, Node CPU + HTTP req/s, Nginx 정적 req/s, Mongo insert/find ops/s | `redis-benchmark`, `node`+`wrk`, `nginx`+`wrk`, `mongod`+`mongosh` |
| **추가** | 컨텍스트 스위치/스레드, **지속 부하 안정성** (열 스로틀링), 프로세스 생성 속도 | `sysbench`, 내장 명령 |

### 워크로드 인덱스

스크립트는 마지막에 **nginx / redis / mongodb / node.js** 및 종합 점수에 대해 정규화된 인덱스
(≈1000 = 기준 클라우드 vCPU, 높을수록 빠름)를 계산합니다. 각 인덱스는 주요 지표의 가중 조합입니다
(예: redis 의 경우 싱글코어 40% + RAM 지연 25% + RAM 대역폭 10% + 실제 redis GET 벤치마크 25%).
인덱스는 가중치의 ≥50% 가 수집된 경우에만 표시됩니다 (오해를 주지 않기 위해). 이 인덱스들은
"서버 A 가 redis 에서 서버 B 보다 얼마나 빠른가"에 답하기 좋은 지표입니다. `≈` 표시는 해당 인덱스가
합성 지표만으로 추정되었음을 의미합니다 (실제 엔진 벤치마크는 실행되지 않음).

## 사용법

```bash
chmod +x benchx.sh
./benchx.sh                       # 표준 (~5분)
./benchx.sh --quick               # 빠름 (~1-2분)
./benchx.sh --thorough            # 정밀 (~15분)
./benchx.sh --json server-a.json  # 리포트 저장
./benchx.sh --no-net              # 네트워크 테스트 생략
./benchx.sh --only cpu,ram        # 해당 분류만
./benchx.sh --skip apps,net       # 분류 생략
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # speedtest 대신 자체 iperf3 서버 사용
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
| `--quick` / `--standard` / `--thorough` | 실행 시간 프로파일 |
| `--no-net` | 네트워크 테스트 생략 |
| `--net-mode speedtest\|latency\|iperf\|none` | 네트워크 테스트 모드 |
| `--iperf-host HOST` | 자체 iperf3 서버 주소 |
| `--target DIR` | 디스크 테스트 디렉터리 (기본값 `.`) |
| `--no-install` | 아무것도 설치하지 않고 이미 있는 도구만 사용 |
| `--yes` | sudo 프롬프트에 자동으로 "예" |
| `--json PATH` | JSON 리포트 경로 |
| `--only CSV` / `--skip CSV` | 분류 필터: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | 색상 없음 (`NO_COLOR` 도 따름) |
| `--compare A.json B.json` | 두 리포트 비교 |

## 의존성과 root

스크립트는 패키지 관리자(Linux 의 `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`, macOS 의 `brew`)를
자동 감지하여 누락된 것을 설치합니다.

- Linux 에서 시스템 패키지 설치에는 **root** 가 필요합니다 —— 스크립트는 `sudo` 사용 허가를 **한 번만** 묻습니다.
- 거부하면 —— **root 없이** 사용 가능한 것만 설치됩니다 (예: `pip --user` 를 통한 `speedtest-cli`).
  나머지는 우아하게 생략되고 "참고" 섹션에 기록됩니다.
- macOS 에서 `brew` 는 root 가 필요 없습니다.
- `--no-install` 은 설치를 완전히 비활성화합니다.

사용할 수 없는 지표는 그냥 생략됩니다 (✓ 완료, ∅ 생략, ✗ 오류) —— 스크립트는 절대 죽지 않습니다.

## 요구 사항

- `bash` (3.2 호환 —— macOS 기본값) 및 표준 유틸리티.
- `--compare` 에는 `python3` **또는** `jq` 가 필요합니다.
- RAM 지연 측정에는 C 컴파일러(`cc`/`gcc`/`clang`)가 필요합니다 —— 없으면 해당 지표는 생략됩니다.

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
- 디스크 테스트는 `--target`(기본값은 현재 디렉터리)에 임시 파일을 쓰고 이후 삭제합니다.
- Speedtest 는 외부 Ookla 서버에 접속합니다. 원치 않으면 `--net-mode iperf` 또는 `--no-net` 을 사용하세요.
- 앱 벤치마크는 `127.0.0.1` 의 임의의 높은 포트에서 서비스를 시작하고 완료 후 종료합니다.

## 라이선스

MIT
