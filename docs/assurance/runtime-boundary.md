# 作業ごとの隔離実行と通信境界の参照構成 (S03 #151 / S04 #153)

[README に戻る](../../README.md) / [保証条件と責任分担](contract.md) / [隔離基盤の選定](runtime-selection.md) / [ADR-0002](../adr/0002-isolated-runtime-orbstack-docker-squid.md) / [ADR-0003](../adr/0003-codex-sandbox-in-containers.md)

## いつ使うか

[最初の対応構成](contract.md#明示選択の保証構成の例-最初の対応構成) (`poc-orbstack-arm64`) で、作業ごとの隔離実行 (AC-PROC-003、AC-PRIV-001〜003)、成果物の取り込み (AC-PRIV-004)、通信の既定拒否 (AC-PRIV-005) の証拠を探すとき、または導入先がこの参照構成の範囲を確かめるとき。資格情報 (AC-PRIV-006・007) は [access-separation.md](access-separation.md) にある。

## この文書が宣言しないこと

- この文書は証拠の所在と限界を示すだけで、どの主張も判定しない。すべての主張は `未検証` である。判定は開発の実行と分けた判定者が行い、所有者が承認する ([採用の条件](contract.md#採用の条件))
- 参照構成は PoC である。架空のデータだけを使い、実モデル・実 GitHub・実 OrbStack の別の版では試していない
- 許可したドメインへの持ち出しはドメインの制限では防げない。[残るリスク](#7-残るリスクと限界) を参照

## 1. 参照構成の所在

実装は隣接リポジトリ aidd-autopilot にある。aidd はその試験と記録の所在を示し、実装は複製しない (運用ルール4「重複禁止」、[runtime-selection.md の §4](runtime-selection.md#4-後続の参照構成の規模見積もり))。

| 項目 | 所在 |
|---|---|
| リポジトリ・コミット | `chun-mura/aidd-autopilot` の [`8469893`](https://github.com/chun-mura/aidd-autopilot/commit/8469893) (ブランチ `feat/assurance-isolated-runtime`)。設計と実装の最初のコミットは `994c276`。その後の修正 (`ab1ac87` 以降) を含む |
| PR | `chun-mura/aidd-autopilot#8`。2026-11-28 に main へマージ済み (マージコミット `66822f8`。記録したコミット `8469893` はその祖先) |
| 設計 | [`docs/superpowers/specs/2026-11-28-assurance-isolated-runtime-design.md`](https://github.com/chun-mura/aidd-autopilot/blob/8469893/docs/superpowers/specs/2026-11-28-assurance-isolated-runtime-design.md)。「実装時の変更」の節が設計からの差分 |
| 実 Docker の試験記録 | [`docs/verification/2026-11-28-assurance-boundary-docker.md`](https://github.com/chun-mura/aidd-autopilot/blob/8469893/docs/verification/2026-11-28-assurance-boundary-docker.md) |
| 段階の実行と制限 (HostConfig・teardown・limits.json) | `packages/platform-docker/src/staged-runner.ts`、`packages/platform-docker/src/run-resources.ts` |
| 通信 (許可先・squid の生成) | `config/egress/{agent,deps,publish}.txt`、`image/proxy/generate-squid-conf.sh`、`packages/platform-docker/src/egress-proxy.ts` |
| 実 Docker の試験 | `tests/docker/*.test.ts` (`npm run test:docker`) |
| モデル CLI の制限 | `packages/workflow-aidd/src/claude-executor.ts` (`--disallowedTools WebFetch,WebSearch`、`--strict-mcp-config`、`--max-budget-usd`) |

aidd 側の検査: `examples/assurance/runtime/check_run_record.py` は、実行が残した `limits.json`・teardown の残数・squid の設定を、Docker を起動せずに検査する ([§5](#5-外部検査-check_run_recordpy))。

## 2. 段階 (stage) と通信

1回の run は、段階ごとの使い捨てコンテナを順に動かす。どの段階も run 専用の `--internal` ネットワークと、同じ run の squid サイドカーを使う (seed と ingest は network none)。

| 段階 | 通信 (既定の許可先) | 種類 | 入力と秘密 | 主な制限 |
|---|---|---|---|---|
| seed | なし (network none) | — | 固定した base commit の bundle (ro)、秘密なし | 読み取り専用の root、tmpfs の上限 |
| deps | `config/egress/deps.txt` の依存レジストリ 11 件 | 依存の取得 | 秘密なし。lockfile がある時だけ `npm ci --ignore-scripts` | 同上 |
| agent | `api.anthropic.com` だけ | モデル接続 | モデルの token を stdin で受け取る。GitHub の token は無い | 同上。SETUID・SETGID だけ追加 (workflow を別 uid で動かすため) |
| ingest | なし (network none) | — | output volume (ro) と、quarantine への書き込みだけ | 上限付きの scratch (tmpfs)、時間上限 |
| publish | `github.com`・`api.github.com` だけ | 公開 | runner の token を stdin で受け取る | 1つの branch への refspec だけ ([access-separation.md](access-separation.md)) |

通信は段階ごとの squid 設定で決まり、設定は run の開始時に固定される。ホストの controller は段階の中に入らない。

## 3. 対象版

ここに書く版は、検証記録 (`docs/verification/2026-11-28-assurance-boundary-docker.md`) で実測したものに限る。版が違えば、主張の判定の前に再検証する ([失効条件](contract.md#失効条件))。

| 構成要素 | 版・識別子 | 出典 |
|---|---|---|
| macOS (ホスト) | 26.7.3 (25G342)、arm64 | 検証記録 (`sw_vers`) |
| OrbStack | 2.2.5 (2020500, commit bf842321f95fc3ca7cda3227bf0cd41cb188c471) | 検証記録 (`orbctl version`) |
| Docker Engine | 29.8.2 (linux/arm64) | 検証記録 |
| VM のカーネル | 7.2.12-orbstack-00394-gbecdd6130068 (aarch64) | 検証記録 (`docker info`) |
| cgroup・seccomp | cgroup v2・cgroupfs・cgroupns、seccomp は builtin の既定プロファイル | 検証記録 |
| VM の資源 | 11 CPU・約 16 GiB | 検証記録 (`docker info`) |
| runner image (修正後の再ビルド、現行) | `sha256:ce88d42430dacac76ff991e44204ea2775561e0d42715d2b90013e1e30a7b63f` | 検証記録の追補 |
| runner image (初回の2回目のビルド) | `sha256:687358e76f963f20009fe6fa55e9da070f85342b7eec716ff040cb10cf767eb8` | 検証記録の本文。現行の値ではない |
| proxy image (最終) | `sha256:d783756d3d92dd6ed583fe60bdf1700613479c61e96362f820d70a192b2e8140` (squid 5.7) | 検証記録 |
| runner の Node.js | v22.23.1 | 検証記録 |
| Claude Code (runner image) | 2.1.216 (`image/Dockerfile` の `@anthropic-ai/claude-code@2.1.216`)。検証記録で `claude --version` が 2.1.216 を返した | 検証記録、Dockerfile |
| 試験したコード | 本文の表は `ae6ba2889080b09aa30af4018690d72067e0119f` で試験した。追補の再実行に使ったコードの SHA は記録に書かれていない (未確認)。記録の最新版は `8469893` | 検証記録 |
| git (runner image) | 未取得 | 検証記録 |

**試験結果 (記録 `8469893` の時点)**: `npm run test:docker` は exit 0、8 ファイル成功、51 成功・1 todo (計 52)。追補の再実行の結果。`npm run test:e2e` は 7 試験成功 (本文の記録)。`npm test` は、記録の本文では 410 試験成功 (修正前の実行)。修正後は、`main` へ取り込む直前のコミット `4a1fe9d` で、437 試験成功・typecheck 成功を確かめた (2026-11-28、開発の実行による確認で、検証記録には載っていない)。

**版の食い違い**: [runtime-selection.md](runtime-selection.md) と [ADR-0002](../adr/0002-isolated-runtime-orbstack-docker-squid.md) は Claude Code を 2.1.207 としている。これは aidd-autopilot の main `cf660fd` の Dockerfile の版で、参照構成 (`8469893`) の Dockerfile は 2.1.216 に固定されている。対象版は 2.1.216 とし、2.1.207 の記述は main の版として読む。判断は所有者が確認する (未確認)。

モデルの認証方式は、対象の設定ファイルでどちらを使うかを確かめていない (資格情報ファイルは読まない)。方式は [access-separation.md](access-separation.md) を参照。

## 4. 主張ごとの対応

状態はすべて `未検証`。下の証拠は、判定者が読むための所在であり、適合の根拠ではない。

**証拠の種類の凡例**: 実 Docker = `tests/docker/` を OrbStack 上で実行した結果。モック = `vitest` の単体試験 (Docker を起動しない)。これはこの文書の証拠に数えない。

### AC-PROC-003 作業ごとの隔離環境が停止・廃棄されている

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/lifecycle.test.ts` (実 Docker、4件): `leaves nothing behind after a normal finish`、`leaves nothing behind after a runner exit with a non-zero code, and records …`、`kills a container that outlives its wall-clock budget and leaves nothing …`、`finds and removes orphaned labeled resources after a simulated host crash`。`tests/docker/staged-run.test.ts` (実 Docker、1件): run の資源が 0 |
| 記録 | 検証記録の最終結果 (`npm run test:docker` exit 0、51 成功・1 todo) |
| 対象版 | §3 のすべて |
| 前提 | OrbStack VM と Docker Engine が正しく止め・削除する。ホストの controller が生きていれば、正常終了・異常終了・時間切れを、ラベルを使って掃除する |
| 限界 | 1 run の所要は約 8 秒。3 run 以上の同時実行・負荷・長時間の run は未確認。ホストの異常終了は模擬した1件の試験だけ (`simulated host crash`) |
| 残りの制限 | 時間の上限は host 側の `docker wait` の期限 (上限 + 猶予) で止める。実 Docker では 1 件だけ確かめた |

### AC-PRIV-001 ホストの home・鍵・daemon の socket・管理 API に届かない

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/host-exposure.test.ts` (実 Docker、直接の探査 4件): `cannot see the host home, /Users, or the Docker socket`、`has no SSH agent socket, even when the host process sets one`、`cannot connect to the cloud metadata address or resolve host.docker.internal` ほか。`tests/docker/concurrency.test.ts` の、run どうしの届かなさ |
| 記録 | 検証記録の AC-PRIV-001・006 の行 (4 成功) |
| 前提 | VM の境界が正しい。ホストの `/Users` は mount しない (設計の「固定コピー」の節) |
| 限界 | コンテナの root は VM の root と同じ uid で、userns の再割り当ては無い。コンテナから VM を抜けた場合に、macOS の何が見えるかは未確認 (ADR 0002) |
| 未確認 | OrbStack の VM が `/Users` を共有している範囲 (VM 自体の共有) は測っていない (runtime-spike 5) |

### AC-PRIV-002 別の実行の作業領域・キャッシュ・一時状態を読み書きせず、引き継がない

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/concurrency.test.ts` (実 Docker、4件): `gives run A's workspace a marker of its own that B's marker is absent from`、`cannot reach run B's holder by IP or by name from run A's network`、`cannot reach run B's proxy from run A's network (IP and name)`、`does not show a new run the files an earlier run left in its workspace or …` |
| 記録 | 検証記録の AC-PRIV-002 の行 (4 成功) |
| 前提 | run ごとに volume・network・proxy の名前が別。tmpfs の volume は run ごとの holder コンテナが持つ (設計の「実装時の変更」3) |
| 限界 | 2 run の組 1 つだけ。3 run 以上・負荷・長時間は未確認 |

### AC-PRIV-003 CPU・メモリ・ディスク・時間の上限が効き、エージェントから変えられない

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/limits.test.ts` (実 Docker、6件): `refuses writes past the tmpfs size with ENOSPC and keeps the file within …`、`kills a memory hog with OOMKilled once the memory limit is reached`、`bounds a fork bomb at the pids limit and leaves the host responsive`、`rejects a write to the root filesystem with EROFS`、`does not let the agent change cgroup limits from inside`、`records the HostConfig values that the limits are applied with`。記録の出力は `<run>/limits.json` (§5) |
| 記録 | 検証記録の測定値 (ENOSPC・OOM・pids・cgroup の値、各 1 回) |
| 前提 | HostConfig の上限は cgroup v2 で効く。ディスクの上限は tmpfs の size で効かせる (overlay2 の `--storage-opt size` は OrbStack で使えない、設計) |
| 限界 | 測定は1回ずつで、ばらつきは見ていない。tmpfs は VM のメモリを使うので、上限の合計が VM を超えないように決める必要がある |
| 未確認 | 512 MiB の bundle の実 Docker での試験 (単体試験だけ)。stage 容器の `Config.Env` は、run の後に削除されるため直接見ていない |

`limits.json` の形 (`staged-runner.ts` の `writeLimits`): 最上位に `schema_version`・`run_id`・`effective` (上限の値)・`stages` (段階名ごとの `exit_code`・`timed_out`・`oom_killed`・`host_config`)・`teardown` (containers・volumes・networks の残数)。`host_config` は HostConfig から Memory・MemorySwap・NanoCpus・PidsLimit・ReadonlyRootfs・CapDrop・CapAdd・SecurityOpt・Tmpfs・Ulimits・NetworkMode・Init だけを抜き出す。`Config.Env` は読まない。

### AC-PRIV-004 成果物を取り込む前に隔離領域で検査し、ホストで自動実行しない

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/ingest.test.ts` (実 Docker、14件): ネットワーク無し、symlink・FIFO・character device の拒否、5000 件の上限、bundle の上限、base..tip の総量の上限、48 MiB の圧縮爆弾、不正な JSON、digest の不一致、余分なファイル、0 commit、自動実行されるパス (`.github/workflows`) |
| 記録 | 検証記録の AC-PRIV-004 の行 (14 成功) |
| 前提 | ingest 段階はネットワーク無し・上限付きの tmpfs・時間上限。ホストは大きさの決まった通常ファイルだけを読み、digest を照合する |
| bundle 作成の拒否 | `unsafe-repository`: workspace・repo ディレクトリが通常でない、alternates で他の object store を借りている、object store が通常のディレクトリでない、grafts・shallow など git の読み方を変える要因がある、config が他のファイルを include している、を bundle 作成の段階で拒否する (commit `ab1ac87`)。試験は `packages/runner/test/branch-bundle.test.ts` (単体、Docker を起動しない) |
| 限界 | 圧縮爆弾の実 Docker 試験は 48 MiB のゼロ。512 MiB の bundle は単体試験のみ。bind mount 越しの device の扱いは未確認 (検証記録の「device node の試験」) |

### AC-PRIV-005 外向き通信は外側で既定拒否され、許可した段階と宛先だけに届く

| 項目 | 内容 |
|---|---|
| 証拠 | `tests/docker/network.test.ts` (実 Docker、9件、うち 8 成功・1 todo): 許可先への HTTPS、平文 HTTP の拒否、IP 直指定・私設網・metadata の 403、3 秒以内の拒否、直接の外部通信と DNS の拒否、他の run の proxy への拒否、段階ごとの許可先の切り替え。todo は HTTP redirect (未確認)。squid の文字列の試験は `packages/platform-docker/test/squid-conf.test.ts` (モック) |
| 記録 | 検証記録の AC-PRIV-005 の行 (8 成功・1 todo)、deny の応答時間の測定 |
| 前提 | `--internal` の network は外へ経路が無い (runtime-spike 2-2 で実測)。squid 5.7 の規則が効く。許可先は段階ごとの `config/egress` の一覧 |
| 限界 | 許可したドメインへの持ち出しは防げない ([§7](#7-残るリスクと限界))。IPv6・redirect の拒否は未確認 |

段階ごとの許可先は、`agent` は `api.anthropic.com` のみ、`deps` は依存レジストリのみ、`publish` は GitHub のみ。`seed` と `ingest` は network none。squid の規則の順序 (設計): `CONNECT` 以外の拒否 → 443 以外の拒否 → IP 直指定の拒否 (文字列での判定、逆引きしない) → 私設網・metadata・CGNAT など解決後の宛先の拒否 → 許可先 (`dstdomain -n`) → 既定の拒否。

## 5. 外部検査 `check_run_record.py`

`examples/assurance/runtime/check_run_record.py` は、run が残した記録を外から検査する (標準ライブラリだけ。Docker も aidd-autopilot も起動しない)。

```bash
python3 examples/assurance/runtime/check_run_record.py --limits <run>/limits.json [--squid-conf <stage>/squid.conf]
```

標準出力は1行の JSON (`{"verdict": "pass" | "fail", "reasons": [...]}`)。終了コードは pass が 0、fail が 1。読めない・解析できない入力は fail (`invalid-input:…`) にする。検査項目は次のとおり。

- 段階ごと: `ReadonlyRootfs`、`CapDrop` が ALL、`no-new-privileges`、`Memory` > 0 かつ `MemorySwap` = `Memory`、`NanoCpus` > 0、`PidsLimit` > 0、tmpfs の size、seed と ingest は `NetworkMode` が none、他の段階は host と bridge でない、`CapAdd` は agent の SETUID・SETGID だけ、`Env` と `Config` を記録していない
- teardown: containers・volumes・networks がすべて 0
- squid (任意): `CONNECT` を要求し、443 だけを許し、`dstdomain -n`、IP 直指定の拒否が許可より前、私設網の拒否が許可より前 (必要な範囲を含む)、既定の拒否が最後、`via off`・`forwarded_for delete`

試験 (`tests/assurance/runtime-record-test.sh`) は、架空の記録 (`tests/assurance/fixtures/runtime-record-cases.json`、30 件) と、aidd-autopilot の生成器の出力を取り込んだ squid の設定 (`tests/assurance/fixtures/runtime-squid-stage.conf`) で検査する。**この検査が通っても、実 run の記録が正しいことにはならない**。実 run の `limits.json` はこの文書の証拠に含まれていない (未確認)。

## 6. 前提と信頼する構成要素

| 項目 | 内容 |
|---|---|
| 前提 | OrbStack の VM 境界が、ホストの home・鍵・管理 API を見せていない。Docker Engine が、HostConfig どおりに上限と network を適用する。squid 5.7 の規則が働く。許可先の名前解決が、私設網を指さない (解決後の拒否で防ぐ) |
| 信頼する構成要素 | OrbStack の VM 境界、Docker Engine、squid (aidd-autopilot の proxy image、digest 固定)、GitHub (publish の宛先)、Anthropic API (agent の宛先) |
| 前提が崩れたとき | VM 境界の脆弱性・Docker の脆弱性は、この参照構成の外にある。公表されたら [失効条件](contract.md#失効条件) に当たる |

## 7. 残るリスクと限界

- **許可したドメインへの持ち出し**: ドメインの制限では防げない。agent の宛先 `api.anthropic.com` には、プロンプトとして workspace の内容と Issue の本文が送られる。publish の宛先 GitHub には、検証済みの branch の内容が push される。deps の宛先の依存レジストリにも、deps 段階は workspace を読めるため、データを送る経路として残る (publish 用の資格情報は deps 段階に無いが、レジストリへの書き込みを防ぐ仕組みは確かめていない)
- **通信の分類**:
  - モデル接続 (agent): モデル API への外部送信として扱う。repo ごとに `repository_model_data_policies` (分類・承認者・承認日) を必須にし、run の記録に写す設計 (aidd-autopilot の CLAUDE.md)。承認が無い repo は dispatch しない
  - 依存の取得 (deps): 承認したレジストリだけ。lockfile がある時だけ `npm ci --ignore-scripts` を実行する
  - 公開 (publish): GitHub だけ。refspec は1つ ([access-separation.md](access-separation.md))
- **MCP・ブラウザ・connector**: claude は `--disallowedTools WebFetch,WebSearch` と `--strict-mcp-config --mcp-config {"mcpServers":{}}` で起動する (`claude-executor.ts`、モックで確認)。`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` でテレメトリを止める (`packages/runner/src/cli.ts`)。ブラウザは image に無いと設計にある (未確認: 実 image での確認は無い)。connector は runner に無い (範囲外として扱う)。shell 経由の通信は、段階の squid の許可先だけに届く
- **ADR 0003 の決定の結果**: 名前空間の syscall (`clone`・`mount`・`pivot_root`・`setns`・`umount2`・`unshare`) は、どの段階にも追加しない。コードに独自の seccomp プロファイルは無く、Docker の既定を使う (`git grep seccomp` で確認)。Codex は runner の workflow で使わない。見直す条件: (a) Codex の read-only レビューを、資格情報とネットワークを持たない専用の段階として追加するとき、(b) 別の基盤 (Linux ホストなど) を採用するとき。その場合は新しい ADR で評価する
- **VM と容器の root**: 同じ uid で userns は無い。カーネルや OrbStack の脆弱性は境界を越えうる
- **tmpfs と VM のメモリ**: tmpfs は VM のメモリを使う。上限の合計が VM のメモリを超えないように決める必要がある
- **GitHub 側の権限**: ruleset・PAT の範囲は実測していない (aidd #230、所有者の承認待ち)
- **model token**: claude の子プロセス (Bash ツール) から読める ([access-separation.md](access-separation.md))

## 8. 未確認

- 実 run の `limits.json` と squid のアクセスログの実物 (token が出ていないこと) の確認
- 3 run 以上の同時実行、負荷、長時間の run
- HTTP redirect の拒否 (todo)、IPv6 の拒否
- 512 MiB の bundle の実 Docker での試験、圧縮爆弾の大きさを上げた試験
- 実 image でのブラウザの不在、runner image の git の版
- stage 容器の `Config.Env` の直接の確認 (設計は秘密を環境変数に入れない)
- OrbStack の利用条件 (費用)、VM の `/Users` 共有の範囲
- Claude Code の版 (2.1.207 と 2.1.216 の食い違い、所有者の確認)
- モデルの認証方式 (所有者の設定)
- 別の OS・基盤 (Docker Desktop・Linux ホスト) での結果

## 9. 判定

この文書は、対象版の証拠の所在と限界を整理した。AC-PROC-003・AC-PRIV-001〜005 の状態は、いずれも `未検証` のままである。判定者 (開発の実行と分けた人か仕組み) と所有者の承認を経ていない。
