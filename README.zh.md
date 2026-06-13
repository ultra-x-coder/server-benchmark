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

一个 bash 脚本，用于测量 CPU、内存、磁盘、网络，以及
**nginx / redis / mongodb / node.js** 的真实性能。它会自行安装依赖，在终端打印整洁的报告，
保存 JSON 报告，并能对比两台服务器/两次运行。

```bash
./benchx.sh                 # 标准运行（约 5 分钟）
```

## 测量内容

| 类别 | 指标 | 工具 |
|------|------|------|
| **CPU** | 单核、多核、线程扩展性、AES-256（TLS）、SHA-256 | `sysbench`、`openssl` |
| **内存** | 读/写带宽（单线程与多线程）、memcpy 带宽、**随机访问延迟**（纳秒） | `sysbench`、`mbw`、即时编译的指针追逐 |
| **磁盘** | 类型（NVMe/SSD/HDD）、随机读/写 IOPS（4k, qd32）、顺序读/写（MB/s）、延迟（平均） | `fio`（回退方案：`dd` + `ioping`） |
| **网络** | 下载/上传（Mbit/s）、空闲延迟、到 1.1.1.1 和 8.8.8.8 的 ping/抖动/丢包 | Ookla `speedtest` / `speedtest-cli`、`ping`、可选 `iperf3` |
| **应用** | Redis SET/GET ops/s、Node CPU + HTTP req/s、Nginx 静态 req/s、Mongo insert/find ops/s | `redis-benchmark`、`node`+`wrk`、`nginx`+`wrk`、`mongod`+`mongosh` |
| **附加** | 上下文切换/线程、**持续负载稳定性**（热降频）、进程创建速率 | `sysbench`、内置命令 |

### 工作负载指数

脚本最后会计算归一化指数（≈1000 = 参考云 vCPU，越高越快），针对
**nginx / redis / mongodb / node.js** 以及一个总分。每个指数是主要指标的加权组合
（例如 redis：单核 40% + 内存延迟 25% + 内存带宽 10% + 真实的 redis GET 基准 25%）。
仅当采集到 ≥50% 的权重时才会显示该指数（以免产生误导）。这些指数正是用来回答
“服务器 A 在 redis 上比服务器 B 快多少”的便捷方式。`≈` 标记表示该指数仅由合成指标估算得出
（未运行真实的引擎基准）。

## 使用方法

```bash
chmod +x benchx.sh
./benchx.sh                       # 标准（约 5 分钟）
./benchx.sh --quick               # 快速（约 1-2 分钟）
./benchx.sh --thorough            # 彻底（约 15 分钟）
./benchx.sh --json server-a.json  # 保存报告
./benchx.sh --no-net              # 跳过网络测试
./benchx.sh --only cpu,ram        # 仅这些类别
./benchx.sh --skip apps,net       # 跳过这些类别
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # 使用你自己的 iperf3 服务器代替 speedtest
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

这会打印一张指标与指数的表格，并给出百分比差异（绿色 = B 更快，红色 = 更慢）。

## 选项

| 参数 | 用途 |
|------|------|
| `--quick` / `--standard` / `--thorough` | 时长档位 |
| `--no-net` | 跳过网络测试 |
| `--net-mode speedtest\|latency\|iperf\|none` | 网络测试模式 |
| `--iperf-host HOST` | 你自己的 iperf3 服务器地址 |
| `--target DIR` | 磁盘测试目录（默认 `.`） |
| `--no-install` | 不安装任何东西，仅使用已存在的工具 |
| `--yes` | 对 sudo 提示自动回答“是” |
| `--json PATH` | JSON 报告的路径 |
| `--only CSV` / `--skip CSV` | 类别过滤：`cpu,ram,disk,net,apps,extras` |
| `--no-color` | 无颜色（同样遵循 `NO_COLOR`） |
| `--compare A.json B.json` | 对比两份报告 |

## 依赖与 root

脚本会自动检测包管理器（Linux 上的 `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`，macOS 上的 `brew`）
并安装缺失项。

- 在 Linux 上安装系统软件包需要 **root** —— 脚本会**仅一次**请求使用 `sudo` 的许可。
- 如果你拒绝 —— 只会安装**无需 root** 即可获得的部分（例如通过 `pip --user` 的 `speedtest-cli`），
  其余项会被优雅跳过，并在“备注”部分注明。
- 在 macOS 上 `brew` 不需要 root。
- `--no-install` 会完全禁用安装。

任何不可用的指标都会被直接跳过（✓ 完成、∅ 跳过、✗ 错误）—— 脚本永不崩溃。

## 环境要求

- `bash`（兼容 3.2 —— macOS 默认版本）及标准工具。
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
- 磁盘测试会在 `--target`（默认当前目录）写入一个临时文件并随后删除。
- Speedtest 会连接外部 Ookla 服务器；若不希望如此，请使用 `--net-mode iperf` 或 `--no-net`。
- 应用基准会在 `127.0.0.1` 的一个随机高端口上启动服务，并在完成后关闭它们。

## 许可证

MIT
