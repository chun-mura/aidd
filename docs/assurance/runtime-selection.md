# 隔離実行基盤の比較と最初の対応構成 (S02 / #150)

いつ読むか: 保証ロードマップ (S03 #151、S04 #153、S05 #154 など) で、エージェントを動かす隔離環境の前提を確かめるとき。決定そのものは [ADR-0002](../adr/0002-isolated-runtime-orbstack-docker-squid.md)、実測の根拠は [runtime-spike.md](runtime-spike.md) にある。

設計の根拠は `docs/superpowers/specs/2026-11-23-assurance-roadmap-design.md` の S02。このファイルは比較と選定の記録であり、どの構成も「安全」と宣言しない。保証する主張とその前提は #149 (`docs/assurance/contract.md`) で定める。**#149 の主張IDへの対応付けは #149 のマージ後に行う。**

## 1. 選んだ構成 (所有者の決定、2026-11-28)

| 項目 | 選択 |
|---|---|
| OS / CPU | macOS (arm64、Apple Silicon) |
| 隔離基盤 | OrbStack の Linux VM 上で、作業ごとに Docker コンテナを1つ起動し、終了後に消す |
| 通信 | 外へ出る経路を持たない `--internal` ネットワークに runner を置き、squid サイドカー (許可ドメインだけ通す) を経由させる。aidd-autopilot の構成を流用する |
| ハーネス | Claude Code (コンテナ内、`claude -p`) |
| モデルの認証方式 | aidd-autopilot が対応する2方式のどちらか: `claude setup-token` で発行する OAuth トークン (`CLAUDE_CODE_OAUTH_TOKEN`) または API キー (`ANTHROPIC_API_KEY`)。設定の `anthropic_auth_mode` で選ぶ。GitHub は対象リポジトリだけの fine-grained PAT (`GH_TOKEN`)。どちらもコンテナへ環境変数で渡る (§2.3) |
| 費用 | 新しい有料契約を結ばない |
| 用途 | 非本番の PoC。本番環境・本番データ・顧客データには使わない |

対応版 (実測した版。これ以外は未確認):

| 構成要素 | 版 |
|---|---|
| macOS | 26.7.3 (arm64) |
| OrbStack | 2.2.5 (VM カーネル 7.2.12-orbstack、cgroup v2) |
| Docker Engine | 29.8.2 (linux/arm64) |
| squid | 5.7 (aidd-autopilot の proxy イメージ。base は `node:22-bookworm` の digest 固定) |
| Claude Code | 2.1.207 (aidd-autopilot main `cf660fd` の `image/Dockerfile` で固定。コンテナ内で実際に起動した版は、この PoC では確かめていない) |

モデルの認証方式のうち、いまの設定がどちらかは確かめていない。設定ファイル (`~/.aidd-autopilot/config.json`) は資格情報を含むので読んでいない。所有者が確認する。

## 2. aidd-autopilot の棚卸し

対象: `aidd-autopilot` main `cf660fd` (2026-08-01)。読んだのは `README.md`、`lib/container.sh`、`lib/config.sh`、`image/Dockerfile`、`image/proxy/*`、`pipeline/common.sh`・`driver.sh`、`tests/container.bats`・`proxy.bats`、`docs/superpowers/specs/2026-07-12-aidd-autopilot-design.md`・`2026-07-31-modular-core-design.md`。

### 2.1 隔離

| 項目 | 現状 | 根拠 |
|---|---|---|
| 単位 | タスク (Issue) ごとに `docker run -d` で runner コンテナを1つ | `lib/container.sh` `container_start` |
| ユーザー | イメージ内の非 root ユーザー `runner` | `image/Dockerfile` |
| 付けている制限 | `--security-opt no-new-privileges`、`--memory` (既定 4g)、`--pids-limit` (既定 512) | `_container_build_run_args` |
| 付けていない制限 | `--read-only`、`--cap-drop ALL`、`--cpus`、ディスク容量、独自の seccomp | 同上。設計書は `--cap-drop`・seccomp を「Linux ホスト移行時に」と後回しにしている |
| ソースの渡し方 | コンテナ内で `gh repo clone` (ホストの固定コピーではない) | `pipeline/driver.sh` |
| ホストとの共有 | ホストのログディレクトリを `/work/artifacts` に読み書き可能で bind mount | `_container_build_run_args` |
| 時間上限 | ホストの watcher が `max_wall_clock_minutes` (既定 120) を超えたら kill | `bin/aidd-autopilot` |
| 予算上限 | フェーズごとに `total_cost_usd` を足し、超えたら止める。`claude -p` に `--max-budget-usd` は付けていない | `pipeline/common.sh` `ap_claude` |
| 終了後 | ログを回収してから `docker rm -f` | `container_capture_logs`・`container_remove` |
| 権限確認 | `claude -p --dangerously-skip-permissions` (自動承認) | `pipeline/common.sh` |

### 2.2 通信 (egress)

| 項目 | 現状 | 根拠 |
|---|---|---|
| 方式 | runner は `--internal` ネットワーク `aidd-autopilot-egress` だけに参加。squid コンテナ `aidd-autopilot-proxy` が bridge とその internal の両方に参加し、`HTTP(S)_PROXY` で使わせる | `container_ensure_egress` |
| 許可先 | Anthropic API・認証、GitHub、npm/PyPI/crates.io/Go/Maven/RubyGems。設定 `egress_allowlist` で追加 (サブドメインも許可) | `AP_EGRESS_DEFAULT_DOMAINS` |
| 規則 | CONNECT は 443 だけ、HTTP は 80 だけ。許可ドメイン以外は `deny all` | `generate-squid-conf.sh` |
| 共有範囲 | ネットワークとプロキシは全タスクで1つ | `AP_EGRESS_NET`・`AP_EGRESS_PROXY` |
| 失敗時 | ネットワーク作成・プロキシ起動のコマンドが失敗すればタスクを始めない | `container_ensure_egress` のコメント |
| 試験 | squid 設定の文字列だけを確かめる。Docker はモックで、実際にコンテナを起動する試験は無い | `tests/proxy.bats`・`tests/container.bats` |

### 2.3 資格情報

| 項目 | 現状 |
|---|---|
| 保管 | ホストの `~/.aidd-autopilot/config.json` (起動時に `chmod 600` を確かめる) |
| 種類 | GitHub の fine-grained PAT (対象リポジトリの contents / pull requests / issues の読み書き)、Anthropic の OAuth トークンまたは API キー |
| 渡し方 | 値を書かない `-e GH_TOKEN` などで環境変数として渡す。argv には出ないが、**`docker inspect` の `.Config.Env` に平文で残る** (runtime-spike 1-4 で架空の値を使って実測) |
| エージェントから見えるか | 見える。自動承認のセッションが同じコンテナで動くので、環境変数を読める |
| 公開の歯止め | 対象リポジトリの main のブランチ保護を前提にしている (README)。PR のマージは人間 |

### 2.4 運用

launchd の watcher が対象リポジトリのラベルを見て起動する。ログは `~/.aidd-autopilot/logs/`、1タスク1行の履歴は `history.jsonl`、状況は `bin/aidd-autopilot status`。イメージは `scripts/build-image.sh` で手元ビルド。runner イメージの base は digest 固定だが、プラグイン (aidd・superpowers) はビルド時の最新 HEAD を取り込む (Dockerfile の NOTE)。controller と runner を分ける再設計 (`2026-07-31-modular-core-design.md`) が未実装のまま残っている。

### 2.5 再利用できるもの・足りないもの・変更を持つべきリポジトリ

| 項目 | 判定 | 変更を持つリポジトリ |
|---|---|---|
| 作業ごとのコンテナ、`no-new-privileges`・`--memory`・`--pids-limit` | 再利用する | — |
| `--internal` + squid サイドカーの既定拒否 | 再利用する (方式は実測で働いた。runtime-spike 2-2、2-5) | — |
| **squid サイドカーが起動しない** (`/dev/stdout` を開けずに FATAL、runtime-spike 2-4) | 不足 (不具合)。いまのビルドのままでは allowlist の構成が成り立たない | aidd-autopilot |
| 起動したコンテナで拒否・許可を確かめる試験 | 不足 (いまは文字列とモックだけ) | aidd-autopilot (実装側の回帰)。保証の主張に対する試験は aidd の S03/S04 |
| `--read-only`・`--cap-drop ALL`・`--cpus`・ディスク上限 | 不足。どれも OrbStack で効くことは実測した (runtime-spike 3) | aidd-autopilot (既定値)。参照構成は aidd の S03 |
| ネットワークとプロキシを全タスクで共有 | 不足。並行する2つの runner が同じ internal ネットワークで互いに届く (未実測) | aidd-autopilot。境界の試験は aidd の S03/S04 |
| ソースをコンテナ内で clone (資格情報を持つエージェントが取りに行く) | 不足。S03 の「固定コピーを渡す」と違う | aidd-autopilot (modular-core の controller/runner 分割と合わせる) |
| ログディレクトリの読み書き bind mount | 不足。成果物の取り込み境界 (パス逸脱・リンク・容量) が無い | aidd-autopilot。境界の定義は aidd の S03 |
| 秘密を環境変数で渡す (`docker inspect` から読める) | 不足 | aidd-autopilot。分離方針と試験は aidd の S05 |
| IP 直打ちの拒否が逆引き待ちで約38秒かかる | 改善候補 (拒否はされる) | aidd-autopilot |
| `claude -p` に `--max-budget-usd` が無い | 改善候補 (フェーズ後の積算はある) | aidd-autopilot |

aidd-autopilot 側の変更はこの Issue では起票しない。必要な変更の一覧は PR 本文と報告に書いた。

## 3. 候補の比較

凡例: **実測** = runtime-spike.md で測った。**文書** = 公式文書・aidd-autopilot の設計書による (この作業では版を確かめていない)。**未確認** = このマシンで測れず、根拠も確かめていない。

候補:

- **A. 作業ごとの VM** (Lima・Tart など、タスクごとに VM を作って消す)
- **B. VM 内の Docker (OrbStack)** — 選んだ構成
- **C. 管理された sandbox** — C1: Claude Code の OS sandbox (macOS Seatbelt。aidd の [ローカルで権限を絞って使う](../guides/local-permissions.md)、#84/#115)。C2: クラウドの sandbox サービス
- **D. Docker Desktop** (macOS 上の VM 内 Docker。B と同じ型)
- **E. rootless Docker** (Linux ホスト上で dockerd を一般ユーザーで動かす)
- 参考 **F. 普通の Docker** (Linux ホスト上の root の dockerd)

| 観点 | A. 作業ごとの VM | B. OrbStack の VM 内 Docker | C1. Claude Code の OS sandbox | C2. クラウドの sandbox | D. Docker Desktop | E. rootless Docker | F. 普通の Docker |
|---|---|---|---|---|---|---|---|
| ホスト共有 | VM ごとにカーネルが別。共有するディレクトリは VM の設定次第 (未確認) | コンテナは VM のカーネルを共有 (実測 1-1)。mount しなければホストの `/Users` は見えない (実測 1-2)。VM 自体が `/Users` をどこまで共有するかは未確認 | 同じ macOS のプロセス。読み書きできるパスを Seatbelt で絞る (文書: local-permissions.md) | 事業者の環境。ホストと共有しない (未確認) | B と同じ型 (未確認) | ホストのカーネルを共有。コンテナの root はホストの一般ユーザーに対応する (文書) | ホストのカーネルを共有。コンテナの root はホストの root と同じ uid (文書。VM 内では実測 1-5) |
| 管理 API | VM 管理コマンド (`limactl` など)。VM の中に Docker を置かなければ docker.sock は無い (未確認) | docker.sock はコンテナに見えない (実測 1-2)。ただし Docker API を使える者はホストのパスを mount できる (実測 1-6) | 無し (Claude Code の設定ファイルを管理側として守る必要がある) | 事業者の API・アカウント (未確認) | B と同じ型 (未確認) | 一般ユーザーの dockerd の socket (文書) | root の docker.sock。使える者はホスト root 相当 (文書) |
| 通信 | VM のネットワーク設定次第。外側で絞るには別途プロキシ・ファイアウォールが要る (未確認) | `--internal` で直接の外向き・metadata・IP 直打ちを拒否 (実測 2-2)。squid で許可ドメインだけ通す (実測 2-5、ただし起動不具合 2-4)。既定 bridge ではホスト (`host.docker.internal`) に届く (実測 2-3) | Claude Code の proxy でドメインを絞る (文書)。Bash 以外の経路 (MCP など) は別 | 事業者の機能次第 (未確認) | B と同じ型 (未確認) | slirp4netns などの利用者空間ネットワーク。`--internal` の効き方は未確認 | `--internal` と iptables。B と同等と考えられるが未確認 |
| 秘密 | 渡し方を自分で作る (未確認) | 環境変数で渡すと `docker inspect` に残る (実測 1-4)。ホストの環境変数は渡さない限り入らない (実測 1-3) | 同じユーザーのプロセスなので、読み取り拒否のパターンに頼る (文書) | 事業者の secret 機能 (未確認) | B と同じ型 (未確認) | F と同じ渡し方 (未確認) | B と同じ (未確認) |
| 資源上限 | VM の CPU・メモリを固定できる (未確認) | `--memory`・`--pids-limit`・`--cpus` が cgroup v2 で効く (実測 3-4〜3-6)。ディスク上限は未確認 | 無し (OS のプロセス上限だけ) | 事業者の上限 (未確認) | B と同じ型 (未確認) | cgroup v2 の委譲があれば効く (文書。未確認) | 効く (文書) |
| 更新 | VM イメージとゲスト OS を自分で更新 (未確認) | OrbStack アプリの更新 + runner イメージの再ビルド (base は digest 固定) | Claude Code の更新に従う | 事業者が更新 | Docker Desktop の更新 | dockerd と OS を自分で更新 | 同左 |
| 廃棄 | VM ごと消せる (未確認) | コンテナを消せば中の状態は残らない (実測 4-1)。名前付きボリュームは残る (実測 4-2) | 作業ディレクトリが残る。廃棄の単位が無い | 事業者の機能次第 (未確認) | B と同じ型 (未確認) | F と同じ (未確認) | B と同じ (未確認) |
| 互換性 | VM イメージを用意すれば何でも動く。起動が遅い (未確認) | linux/arm64 のイメージ。amd64 は Rosetta で動く (実測: `node:22` amd64 の curl が動いた)。aidd-autopilot がそのまま動く前提 | macOS のツールがそのまま動く。Linux 専用のものは動かない | 事業者の対応範囲 (未確認) | B と同じ型 | 一部の機能 (特権ポート、一部のストレージドライバ) に制約 (文書) | 最も広い |
| 費用 | 無料のツールあり (Lima)。費用は未確認 | **利用条件は所有者が確認する** (この作業では OrbStack のライセンス文面を確かめていない) | Claude Code の利用料の範囲 | 有料契約が要る (対象外) | **利用条件は所有者が確認する** (この作業では確かめていない) | 無料 (Linux ホストが要る) | 無料 (Linux ホストが要る) |
| 運用担当 | 所有者 (VM の作成・更新・廃棄) | 所有者 (OrbStack とイメージ)。runner の起動・廃棄は aidd-autopilot | 利用者 (Claude Code の設定) | 事業者 + 契約者 | 所有者 | Linux ホストの管理者 | 同左 |
| このマシンで測ったか | 未確認 (`limactl` 2.1.2 はあるがインスタンス無し) | 実測 | aidd の既存手順。この PoC では再測定していない | 未確認 (対象外) | 未確認 (デーモンに接続できない) | 未確認 (Linux 専用) | 未確認 (Linux ホストが無い) |

### B を選ぶ理由と残るもの

- 既存の aidd-autopilot がこの構成で動いており、隔離・通信・廃棄の方式を作り直さずに使える (S02 の「新規の汎用 runtime を作らない」に合う)。
- 実測で、ホストの home・docker.sock が見えないこと、`--internal` で直接の外向き・metadata が拒否されること、資源上限と廃棄が効くことを確かめた。
- macOS では VM がホストのカーネルとコンテナの間に入る。ただしコンテナの root は VM の root と同じ uid で (実測 1-5)、userns の再割り当ては無い。コンテナから VM に抜けた場合に macOS の何が見えるかは未確認。
- C1 (Claude Code の OS sandbox) は通常利用の手順として残し、置き換えない。B は「強い保証を求める明示選択の構成」側に置く (#149 の区分に合わせる)。
- A は VM 単位の分離が強いが、起動と更新の手間が大きく、このマシンで測っていない。B で足りないと #149 の主張で判明したら、aidd-autopilot の設計書どおり起動部分を VM に差し替える候補にする。

## 4. 後続の参照構成の規模見積もり

ロードマップの配置案と、この比較で見つかった不足から数えた。「主要ファイル」は README の索引・CHANGELOG・manifest・生成物を除く。Docker を要する試験は、いまの CI の contract-tests (ubuntu と macOS のマトリクス) に入れられない (GitHub の macOS ランナーには Docker が無い。未確認) ため、CI のジョブ追加と `.claude/CLAUDE.md` のテスト一覧の更新も数に入れた。

| Issue | 主要ファイル (案) | 数 | 判断 |
|---|---|---|---|
| S03 #151 作成・破棄 | `examples/assurance/runtime/run-task.sh` (docker run の引数を固定する包み)、`examples/assurance/runtime/README.md`、`tests/assurance/runtime-lifecycle-test.sh`、`.github/workflows/validate.yml` (Docker の要るジョブ)、成果物の取り込み (`examples/assurance/runtime/import-artifacts.sh` とその試験) | 6〜7 | **超える。実装前に分割する**: (a) 作成・資源上限・廃棄・並行2実行、(b) 成果物の取り込み境界 (パス逸脱・リンク・容量・ファイル数・時間) |
| S04 #153 通信 | `examples/assurance/network/squid.conf` (または生成規則)、`examples/assurance/network/README.md`、`tests/assurance/network-boundary-test.sh`、CI ジョブ (S03 と共有できれば 0) | 3〜4 | 5件に収まる見込み。ただし直接 IP・IPv6・DNS・redirect・私設網・metadata・代理経路の試験先を1ファイルに入れると大きくなるので、試験先の準備を共通化できるか実装前に確かめる |
| S05 #154 資格情報 | `docs/assurance/credentials.md`、`examples/assurance/credentials/` (fine-grained PAT の範囲と渡し方の例)、`tests/assurance/credentials-boundary-test.sh` | 3 | 5件に収まる見込み。環境変数が `docker inspect` に残る件 (実測 1-4) の代わりの渡し方を決める必要がある |

前提として決めておくこと (実装前に所有者・コーディネーターが選ぶ):

- **実装の置き場所**: ロードマップは参照構成を aidd の `examples/assurance/` に置く案だが、docker の起動・squid は aidd-autopilot の責務と重なる (aidd の運用ルール4「重複禁止」)。(1) aidd には試験と README だけを置き、起動の実装は aidd-autopilot のものを参照する、(2) aidd に最小の参照実装を置き、aidd-autopilot はそれに合わせる、のどちらかを選ぶ。(1) なら S03/S04 の主要ファイルは各1〜2件減る。
- **squid の起動不具合 (runtime-spike 2-4) を aidd-autopilot で先に直すか**。直らない間は、S04 の試験は PoC と同じ回避 (access log をファイルへ) を使うことになる。

## 5. 未確認のまま残すもの

runtime-spike.md の「このマシンで測れなかったもの」を参照。とくに、普通の Docker・rootless・作業ごとの VM・Docker Desktop の違いは文書による記述だけで、実測していない。OrbStack と Docker Desktop の利用条件 (費用) も確かめていない。
