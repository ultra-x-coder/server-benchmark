# benchx — 服务器性能基准测试（Linux / macOS）

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

[English](README.md) · **简体中文** · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Español](README.es.md)

一个 bash 脚本，用于测量 CPU、内存、磁盘、网络，以及 **nginx / redis / mongodb / node.js** 的真实性能。
它**默认不安装任何依赖**，在终端打印整洁的报告，保存 JSON 报告，并能对比两台服务器。默认运行**可安全地在生产服务器上运行**（不安装、不 sudo、不询问，缺少工具的指标会自动跳过）；如需安装缺失的软件包，请使用 `--install` 显式开启。

```bash
chmod +x benchx.sh
./benchx.sh            # 标准运行（约 5 分钟）
./benchx.sh --safe     # 生产安全运行（在线上服务器推荐）
```

## 在生产服务器上运行

使用 **`--safe`**（先用 `--dry-run` 预览）：

```bash
./benchx.sh --safe --dry-run   # 显示将要发生的一切，然后退出
./benchx.sh --safe             # 安全运行
./benchx.sh --safe --skip disk # 安全运行且完全不写磁盘
```

`--safe` 保证：

- **不安装任何软件包、不使用 `sudo`、不改动服务** —— 你的 `/etc` 配置和运行中的守护进程绝不会被触碰；
- **低 CPU/IO 优先级**（`nice 19` + `ionice -c3`）—— 生产进程保留 CPU 与磁盘；
- **网络仅测延迟**（只 ping，不占满带宽）；
- **跳过持续满载压力测试**；
- **仅写入私有临时目录**（+ `--json`），**绝不覆盖已有文件**；
- **磁盘测试先检查可用空间**，会自我缩减或跳过，而不是写满磁盘。

这些保护在非 `--safe` 模式下同样在关键处生效：脚本不会覆盖已存在的 `--json`（除非 `--yes`），不覆盖任何已有文件
（只写唯一临时路径），磁盘测试前检查空间，应用服务绑定到 `127.0.0.1` 的随机高端口，并且 **Ctrl-C 会立即停止并清理**
（不留下孤儿服务或临时文件）。

## 测量内容

| 类别 | 指标 | 工具 |
|------|------|------|
| **CPU** | 单核、多核、线程扩展性、AES-256（TLS）、SHA-256 | `sysbench`、`openssl` |
| **内存** | 读/写带宽（单线程与多线程）、memcpy 带宽、**随机访问延迟**（纳秒） | `sysbench`、`mbw`、即时编译的指针追逐 |
| **磁盘** | 类型（NVMe/SSD/HDD）、随机读/写 IOPS（4k, qd32）、顺序读/写（MB/s）、延迟 | `fio`（回退：`dd` + `ioping`） |
| **网络** | 下载/上传（Mbit/s）、空闲延迟、到 1.1.1.1 和 8.8.8.8 的 ping/抖动/丢包 | Ookla `speedtest` / `speedtest-cli`、`ping`、可选 `iperf3` |
| **应用** | Redis SET/GET ops/s、Node CPU + HTTP req/s、Nginx 静态 req/s、Mongo insert/find ops/s | `redis-benchmark`、`node`+`wrk`、`nginx`+`wrk`、`mongod`+`mongosh` |
| **附加** | 上下文切换/线程、持续负载稳定性（热降频）、进程创建速率 | `sysbench`、内置命令 |

### 工作负载指数

脚本最后会为 **nginx / redis / mongodb / node.js** 及总分计算归一化指数（≈1000 = 参考云 vCPU，越高越快）。
每个指数是主要指标的加权组合（例如 redis：单核 40% + 内存延迟 25% + 内存带宽 10% + 真实 redis GET 基准 25%）。
**仅当该引擎的真实基准确实运行过时才显示对应指数** —— 若 `mongod` 不可用，则不会出现 MongoDB 指数。
这些指数正是用于回答“服务器 A 在 redis 上比 B 快多少”的便捷方式。

## 使用方法

```bash
./benchx.sh                       # 标准（约 5 分钟）
./benchx.sh --quick               # 快速（约 1-2 分钟）
./benchx.sh --thorough            # 彻底（约 15 分钟）
./benchx.sh --safe                # 生产安全
./benchx.sh --dry-run             # 打印计划并退出（不做任何更改）
./benchx.sh --no-install          # 仅使用已存在的工具（默认行为：不安装、不询问）
./benchx.sh --install             # 允许安装缺失的软件包（先警告，需要 sudo，逐个软件包询问）
./benchx.sh --install --yes       # 安装全部，不逐个询问（非交互式运行）
./benchx.sh --net-mode none       # 跳过网络测试
./benchx.sh --json server-a.json  # 保存报告
./benchx.sh --only cpu,ram        # 仅这些类别
./benchx.sh --skip apps,net       # 跳过类别
```

### 对比两台服务器

```bash
# 在服务器 A 上：
./benchx.sh --json a.json
# 在服务器 B 上：
./benchx.sh --json b.json
# 在任意位置：
./benchx.sh --compare a.json b.json
```

打印一张指标与指数的表格，并给出百分比差异（绿色 = B 更快，红色 = 更慢）。

## 选项

| 参数 | 用途 |
|------|------|
| `--quick` / `--thorough` | 时长档位（默认 standard，约 5 分钟） |
| `--safe` | 生产安全：不安装/不 sudo/不改服务，低 CPU/IO 优先级，网络仅延迟，跳过压力测试，不覆盖文件 |
| `--dry-run` | 打印将要发生的一切，然后退出（不更改、不运行基准） |
| `--no-install` | 默认行为：仅用已存在的工具运行，不安装、不 sudo、不询问 |
| `--install` | 选择启用安装缺失的软件包：先显示醒目警告，请求 `sudo`，并在安装每个软件包前逐个询问（这样你可以挑选要装哪些、跳过其余），即隐含 `--confirm-each`；加上 `--yes` 可跳过这些逐个询问 |
| `--reinstall` | 强制重装所需软件包（同时修复 Ctrl-C 后损坏的 dpkg） |
| `--confirm-each` | 安装/重装每个软件包前询问 |
| `--yes` / `-y` | 假定“是”：不询问；同时允许覆盖已有的 `--json` 文件 |
| `--net-mode MODE` | 网络测试模式：`speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | 你自己的 iperf3 服务器地址（设置 `--net-mode iperf`） |
| `--target DIR` | 磁盘测试目录（默认 `.`） |
| `--only CSV` / `--skip CSV` | 类别过滤：`cpu,ram,disk,net,apps,extras` |
| `--json PATH` | JSON 报告路径 |
| `--no-color` | 无颜色（同样遵循 `NO_COLOR`） |
| `--compare A.json B.json` | 对比两份报告并退出 |
| `-h` / `--help` | 帮助 |

## 依赖与 root

脚本**默认不安装任何软件包** —— 它只使用已存在的工具，缺失工具的指标会被优雅跳过。
这使得默认运行可安全地在生产服务器上执行（不安装、不 sudo、不询问）。

- 仅当显式传入 **`--install`** 时，脚本才会检测包管理器（Linux 上的 `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`，
  macOS 上的 `brew`）并安装缺失项。此时它会：
  - **先显示一条醒目的红色警告** —— 软件包（重）安装可能破坏运行中的服务器（覆盖 `/etc` 配置、
    重启或中断 redis/nginx/mongodb 等服务、拉入改变行为的升级）；
  - 在 Linux 上安装系统软件包需要 **root** —— 脚本会**仅一次**请求使用 `sudo` 的许可；
  - 在交互式终端上，会在执行任何操作前请求确认；
  - **会在安装每个软件包前逐个询问**（这样你可以挑选要安装哪些、跳过其余 —— 与 `--confirm-each` 行为相同，`--install` 现已隐含该行为）；加上 **`--yes`** 则跳过这些逐个询问，直接全部安装（用于非交互式运行）。
- 不使用 `--install`（即默认，或显式 `--no-install`/`--safe`）时，只使用已存在的工具，其余优雅跳过并注明。
- 在 macOS 上 `brew` 不需要 root。
- `--reinstall` 修复损坏的 `dpkg` 状态（例如被中断的 `apt` 之后）并强制重装软件包。
  它会**先显示醒目的警告** —— 重装可能覆盖自定义的 `/etc` 配置并重启服务；不会删除你的数据，
  但在生产服务器上更推荐 `--no-install`/`--safe`。

任何不可用的指标都会被直接跳过（✓ 完成、∅ 跳过、✗ 错误）—— 脚本永不崩溃。

## 环境要求

- `bash`（兼容 3.2 —— macOS 默认）及标准工具。
- `--compare` 需要 `python3` **或** `jq`。
- 内存延迟需要 C 编译器（`cc`/`gcc`/`clang`）—— 否则跳过该指标。

## JSON 报告

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

## 精度说明

- 请在空闲的机器上运行；在“吵闹的邻居”（虚拟化）环境下结果会波动 —— 使用 `--thorough`。
  注意：`--safe` 以低优先级运行，因此其数值反映的是空闲容量而非峰值吞吐。
- 磁盘测试会在 `--target`（默认当前目录）写入一个唯一的临时文件并随后删除。
- Speedtest 会连接外部 Ookla 服务器；若不希望如此，请使用 `--net-mode latency` 或 `--net-mode none`。
- 应用基准会在 `127.0.0.1` 的随机高端口上启动服务，并在完成后关闭它们。

## 许可证

MIT
