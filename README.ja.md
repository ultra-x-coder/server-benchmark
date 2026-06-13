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

CPU・RAM・ディスク・ネットワークに加え、**nginx / redis / mongodb / node.js** の実性能を測定する単一の bash スクリプトです。
依存関係を自動インストールし、見やすいターミナルレポートを表示し、JSON レポートを保存し、2 台のサーバーを比較できます。
**本番サーバーでも安全に実行できる**よう設計されています。

```bash
chmod +x benchx.sh
./benchx.sh            # 標準実行（約 5 分）
./benchx.sh --safe     # 本番安全実行（稼働中サーバーで推奨）
```

## 本番サーバーでの実行

**`--safe`** を使ってください（まず `--dry-run` でプレビュー）：

```bash
./benchx.sh --safe --dry-run   # 何が起きるかを表示して終了
./benchx.sh --safe             # 安全実行
./benchx.sh --safe --skip disk # ディスク書き込みゼロで安全実行
```

`--safe` の保証：

- **パッケージのインストールなし・`sudo` なし・サービス変更なし** —— `/etc` の設定や稼働中のデーモンには一切触れません；
- **低い CPU/IO 優先度**（`nice 19` + `ionice -c3`）—— 本番プロセスが CPU とディスクを優先；
- **ネットワークは遅延のみ**（ping のみ、帯域を飽和させない）；
- **持続フルロードのストレステストをスキップ**；
- **書き込みは専用の一時ディレクトリのみ**（+ `--json`）、既存ファイルを**決して上書きしない**；
- **ディスクテストはまず空き容量を確認**し、ディスクを埋める代わりに縮小またはスキップ。

これらの保護は `--safe` 以外でも要所で有効です：既存の `--json` を上書きせず（`--yes` なしでは）、既存ファイルも上書きせず
（一意な一時パスにのみ書き込み）、ディスクテスト前に空き容量を確認し、アプリサーバーを `127.0.0.1` のランダムな高位ポートに
バインドし、**Ctrl-C で即座に停止して後始末します**（孤児プロセスや残骸の一時ファイルなし）。

## 測定内容

| カテゴリ | 指標 | ツール |
|----------|------|--------|
| **CPU** | シングルコア、マルチコア、スレッドスケーリング、AES-256（TLS）、SHA-256 | `sysbench`、`openssl` |
| **RAM** | 読み書き帯域（シングル／マルチスレッド）、memcpy 帯域、**ランダムアクセス遅延**（ns） | `sysbench`、`mbw`、その場でコンパイルするポインターチェイス |
| **ディスク** | 種別（NVMe/SSD/HDD）、ランダム読み書き IOPS（4k, qd32）、シーケンシャル読み書き（MB/s）、遅延 | `fio`（フォールバック: `dd` + `ioping`） |
| **ネットワーク** | ダウンロード／アップロード（Mbit/s）、アイドル遅延、1.1.1.1 と 8.8.8.8 への ping/ジッター/ロス | Ookla `speedtest` / `speedtest-cli`、`ping`、任意で `iperf3` |
| **アプリ** | Redis SET/GET ops/s、Node CPU + HTTP req/s、Nginx 静的 req/s、Mongo insert/find ops/s | `redis-benchmark`、`node`+`wrk`、`nginx`+`wrk`、`mongod`+`mongosh` |
| **追加** | コンテキストスイッチ／スレッド、持続負荷の安定性（サーマルスロットリング）、プロセス生成速度 | `sysbench`、組み込み |

### ワークロード指数

スクリプトは最後に **nginx / redis / mongodb / node.js** と総合スコアについて、正規化された指数
（≈1000 = 基準クラウド vCPU、高いほど高速）を算出します。各指数は主要指標の加重ブレンドです
（例: redis ではシングルコア 40% + RAM 遅延 25% + RAM 帯域 10% + 実際の redis GET ベンチマーク 25%）。
指数は**そのエンジンの実ベンチマークが実際に実行された場合のみ**表示されます —— `mongod` が無ければ MongoDB 指数は
現れません。これらの指数は「サーバー A は redis でサーバー B よりどれだけ速いか」に答えるのに便利です。

## 使い方

```bash
./benchx.sh                       # 標準（約 5 分）
./benchx.sh --quick               # 高速（約 1〜2 分）
./benchx.sh --thorough            # 徹底（約 15 分）
./benchx.sh --safe                # 本番安全
./benchx.sh --dry-run             # 計画を表示して終了（何も変更しない）
./benchx.sh --no-install          # 既存のツールのみで実行（インストール・確認なし）
./benchx.sh --net-mode none       # ネットワークテストをスキップ
./benchx.sh --json server-a.json  # レポートを保存
./benchx.sh --only cpu,ram        # これらのカテゴリのみ
./benchx.sh --skip apps,net       # カテゴリをスキップ
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
| `--quick` / `--thorough` | 実行時間プロファイル（既定 standard、約 5 分） |
| `--safe` | 本番安全：インストール/sudo/サービス変更なし、低 CPU/IO 優先度、遅延のみ、ストレステスト省略、ファイル非上書き |
| `--dry-run` | 何が起きるかを表示して終了（変更・ベンチマークなし） |
| `--no-install` | 既存のツールのみで実行：インストール・sudo・確認なし |
| `--reinstall` | 必要パッケージを強制再インストール（Ctrl-C 後に壊れた dpkg も修復） |
| `--confirm-each` | 各パッケージのインストール/再インストール前に確認 |
| `--yes` / `-y` | 「はい」を仮定：確認なし；既存の `--json` ファイル上書きも許可 |
| `--net-mode MODE` | ネットワークテストモード：`speedtest` \| `latency` \| `iperf` \| `none` |
| `--iperf-host HOST` | 自前の iperf3 サーバーのアドレス（`--net-mode iperf` を設定） |
| `--target DIR` | ディスクテスト用ディレクトリ（既定値 `.`） |
| `--only CSV` / `--skip CSV` | カテゴリフィルタ：`cpu,ram,disk,net,apps,extras` |
| `--json PATH` | JSON レポートのパス |
| `--no-color` | 色なし（`NO_COLOR` も尊重） |
| `--compare A.json B.json` | 2 つのレポートを比較して終了 |
| `-h` / `--help` | ヘルプ |

## 依存関係と root

スクリプトはパッケージマネージャ（Linux の `apt`/`dnf`/`yum`/`pacman`/`zypper`/`apk`、macOS の `brew`）を自動検出し、不足分をインストールします。

- Linux ではシステムパッケージのインストールに **root** が必要です —— スクリプトは `sudo` 使用の許可を **一度だけ** 尋ねます。
- 拒否した場合（または `--no-install`/`--safe`）、**root なし** で使えるものだけを使い、それ以外は丁寧にスキップ・記録します。
  公式の **Ookla `speedtest` CLI は tarball から root なしで**（`~/.local/bin` に）インストールされます。
- macOS では `brew` に root は不要です。
- `--reinstall` は壊れた `dpkg` 状態（例: 中断された `apt` の後）を修復し、パッケージを強制再インストールします。
  まず**目立つ警告**を表示します —— 再インストールはカスタマイズした `/etc` 設定を上書きし、サービスを再起動する可能性があります。
  データは削除しませんが、本番サーバーでは `--no-install`/`--safe` を推奨します。

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
  注意: `--safe` は低優先度で実行されるため、その数値はピーク性能ではなく空き容量を反映します。
- ディスクテストは `--target`（既定はカレントディレクトリ）に一意の一時ファイルを書き込み、その後削除します。
- Speedtest は外部の Ookla サーバーに接続します。望ましくない場合は `--net-mode latency` または `--net-mode none` を使用してください。
- アプリのベンチマークは `127.0.0.1` のランダムな高位ポートでサービスを起動し、完了後に停止します。

## ライセンス

MIT
