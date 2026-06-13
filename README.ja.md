# benchx — サーバー性能ベンチマーク（Linux / macOS）

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

[English](README.md) · [简体中文](README.zh.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · **日本語** · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Español](README.es.md)

CPU・RAM・ディスク・ネットワークに加え、**nginx / redis / mongodb / node.js** の実性能を測定する
単一の bash スクリプトです。依存関係を自動インストールし、見やすいターミナルレポートを表示し、
JSON レポートを保存し、2 台のサーバー／2 回の実行を比較できます。

```bash
./benchx.sh                 # 標準実行（約 5 分）
```

## 測定内容

| カテゴリ | 指標 | ツール |
|----------|------|--------|
| **CPU** | シングルコア、マルチコア、スレッドスケーリング、AES-256（TLS）、SHA-256 | `sysbench`、`openssl` |
| **RAM** | 読み書き帯域（シングル／マルチスレッド）、memcpy 帯域、**ランダムアクセス遅延**（ns） | `sysbench`、`mbw`、その場でコンパイルするポインターチェイス |
| **ディスク** | 種別（NVMe/SSD/HDD）、ランダム読み書き IOPS（4k, qd32）、シーケンシャル読み書き（MB/s）、遅延（平均） | `fio`（フォールバック: `dd` + `ioping`） |
| **ネットワーク** | ダウンロード／アップロード（Mbit/s）、アイドル遅延、1.1.1.1 と 8.8.8.8 への ping/ジッター/ロス | Ookla `speedtest` / `speedtest-cli`、`ping`、任意で `iperf3` |
| **アプリ** | Redis SET/GET ops/s、Node CPU + HTTP req/s、Nginx 静的 req/s、Mongo insert/find ops/s | `redis-benchmark`、`node`+`wrk`、`nginx`+`wrk`、`mongod`+`mongosh` |
| **追加** | コンテキストスイッチ／スレッド、**持続負荷の安定性**（サーマルスロットリング）、プロセス生成速度 | `sysbench`、組み込み |

### ワークロード指数

スクリプトは最後に **nginx / redis / mongodb / node.js** と総合スコアについて、正規化された指数
（≈1000 = 基準のクラウド vCPU、高いほど高速）を算出します。各指数は主要指標の加重ブレンドです
（例: redis ではシングルコア 40% + RAM 遅延 25% + RAM 帯域 10% + 実際の redis GET ベンチマーク 25%）。
指数は重みの 50% 以上が収集できた場合にのみ表示されます（誤解を招かないため）。これらの指数は
「サーバー A は redis でサーバー B よりどれだけ速いか」に答えるのに便利です。`≈` の印は、その指数が
合成指標のみによる推定であること（実エンジンのベンチマークは未実行）を示します。

## 使い方

```bash
chmod +x benchx.sh
./benchx.sh                       # 標準（約 5 分）
./benchx.sh --quick               # 高速（約 1〜2 分）
./benchx.sh --thorough            # 徹底（約 15 分）
./benchx.sh --json server-a.json  # レポートを保存
./benchx.sh --no-net              # ネットワークテストをスキップ
./benchx.sh --only cpu,ram        # これらのカテゴリのみ
./benchx.sh --skip apps,net       # カテゴリをスキップ
./benchx.sh --net-mode iperf --iperf-host 10.0.0.5   # speedtest の代わりに自前の iperf3 サーバーを使用
```

### 2 台のサーバーを比較

```bash
# サーバー A で:
./benchx.sh --json a.json
# サーバー B で:
./benchx.sh --json b.json
# どこでも:
./benchx.sh --compare a.json b.json
```

指標と指数を百分率の差とともに表で出力します（緑 = B が高速、赤 = 低速）。

## オプション

| フラグ | 用途 |
|--------|------|
| `--quick` / `--standard` / `--thorough` | 実行時間プロファイル |
| `--no-net` | ネットワークテストをスキップ |
| `--net-mode speedtest\|latency\|iperf\|none` | ネットワークテストのモード |
| `--iperf-host HOST` | 自前の iperf3 サーバーのアドレス |
| `--target DIR` | ディスクテスト用ディレクトリ（既定値 `.`） |
| `--no-install` | 何もインストールせず、既にあるツールのみ使用 |
| `--yes` | sudo の確認に自動で「はい」 |
| `--json PATH` | JSON レポートのパス |
| `--only CSV` / `--skip CSV` | カテゴリフィルタ: `cpu,ram,disk,net,apps,extras` |
| `--no-color` | 色なし（`NO_COLOR` も尊重） |
| `--compare A.json B.json` | 2 つのレポートを比較 |

## 依存関係と root

スクリプトはパッケージマネージャ（Linux の `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`、macOS の `brew`）を
自動検出し、不足分をインストールします。

- Linux ではシステムパッケージのインストールに **root** が必要です —— スクリプトは `sudo` 使用の許可を **一度だけ** 尋ねます。
- 拒否した場合 —— **root なし** で利用可能なものだけがインストールされます（例: `pip --user` による `speedtest-cli`）。
  それ以外は丁寧にスキップされ、「メモ」セクションに記録されます。
- macOS では `brew` に root は不要です。
- `--no-install` はインストールを完全に無効化します。

利用できない指標は単純にスキップされます（✓ 完了、∅ スキップ、✗ エラー）—— スクリプトはクラッシュしません。

## 要件

- `bash`（3.2 互換 —— macOS の既定）と標準ユーティリティ。
- `--compare` には `python3` **または** `jq` が必要です。
- RAM 遅延には C コンパイラ（`cc`/`gcc`/`clang`）が必要です —— なければその指標はスキップされます。

## JSON レポート

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

## 精度に関する注意

- アイドル状態のマシンで実行してください。「うるさい隣人」（仮想化）の環境では結果がばらつきます —— `--thorough` を使用してください。
- ディスクテストは `--target`（既定はカレントディレクトリ）に一時ファイルを書き込み、その後削除します。
- Speedtest は外部の Ookla サーバーに接続します。望ましくない場合は `--net-mode iperf` または `--no-net` を使用してください。
- アプリのベンチマークは `127.0.0.1` のランダムな高位ポートでサービスを起動し、完了後に停止します。

## ライセンス

MIT
